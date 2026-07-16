with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C.Strings;

with System;
with Interfaces;
with System.Storage_Elements;
with Ada.Strings.Unbounded;

package body Hostkit.Fs is

   use type Ada.Directories.File_Kind;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Invalid_File_Attributes      : constant C_DWord := 16#FFFF_FFFF#;
   File_Attribute_Reparse_Point : constant C_DWord := 16#0000_0400#;
   File_Attribute_Directory     : constant C_DWord := 16#0000_0010#;

   Symbolic_Link_Allow_Unprivileged : constant C_DWord := 16#0000_0002#;
   Symbolic_Link_Directory          : constant C_DWord := 16#0000_0001#;

   function Get_File_Attributes
     (Name : Interfaces.C.Strings.chars_ptr)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetFileAttributesA";

   function Create_Symbolic_Link
     (Link   : System.Address;
      Target : System.Address;
      Flags  : C_DWord)
      return Interfaces.C.char
     with Import => True, Convention => Stdcall, External_Name => "CreateSymbolicLinkW";

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

   --  A symbolic link and a junction are both reparse points, and this is how Windows
   --  says so. There is no lstat, which is why GNAT's Is_Symbolic_Link cannot answer
   --  here and says False instead.
   function Is_Link (Path : String) return Boolean is
      C_Path     : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Attributes : constant C_DWord := Get_File_Attributes (C_Path);
   begin
      Interfaces.C.Strings.Free (C_Path);

      return Attributes /= Invalid_File_Attributes
        and then (Attributes and File_Attribute_Reparse_Point) /= 0;
   exception
      when others =>
         return False;
   end Is_Link;

   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean
   is
      Wide_Target : aliased Wide_String := Wide (Target);
      Wide_Link   : aliased Wide_String := Wide (Link_Path);

      Is_Directory : constant Boolean :=
        (Ada.Directories.Exists (Target)
         and then Ada.Directories.Kind (Target) = Ada.Directories.Directory);

      --  Windows will not make a link without either Developer Mode or the privilege,
      --  and refusing is a normal answer here rather than a fault.
      Flags : constant C_DWord :=
        Symbolic_Link_Allow_Unprivileged
        + (if Is_Directory then Symbolic_Link_Directory else 0);

      Created : constant Interfaces.C.char :=
        Create_Symbolic_Link (Wide_Link'Address, Wide_Target'Address, Flags);
   begin
      return Interfaces.C.char'Pos (Created) /= 0;
   exception
      when others =>
         return False;
   end Create_Link;

   --  Windows does not decide what runs from a mode bit. Every ordinary file is granted
   --  FILE_EXECUTE in its DACL, so folding that in said everything was executable -- and
   --  a file manager duly classified a .tar.gz as a program. What runs here is decided
   --  by the extension.
   function Is_Executable (Path : String) return Boolean is
      Runnable : constant array (1 .. 6) of access constant String :=
        [new String'(".exe"), new String'(".com"), new String'(".bat"),
         new String'(".cmd"), new String'(".ps1"), new String'(".msi")];

      C_Path     : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Attributes : constant C_DWord := Get_File_Attributes (C_Path);
   begin
      Interfaces.C.Strings.Free (C_Path);

      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Directory) /= 0
      then
         return False;
      end if;

      for Suffix of Runnable loop
         declare
            Text : constant String := Suffix.all;
         begin
            if Path'Length >= Text'Length
              and then Ada.Characters.Handling.To_Lower
                         (Path (Path'Last - Text'Length + 1 .. Path'Last)) = Text
            then
               return True;
            end if;
         end;
      end loop;

      return False;
   exception
      when others =>
         return False;
   end Is_Executable;

   --  No mode bits on Windows; access is by ACL, and reading it is not done here. Answer
   --  False -- decline to guess rather than reject a key the profile ACL already protects.
   function Accessible_By_Others (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Accessible_By_Others;

   --  MoveFileEx with MOVEFILE_REPLACE_EXISTING is the atomic replacing rename Windows
   --  offers; plain rename (and GNAT.OS_Lib.Rename_File) fails when the target exists.
   function Replace_File
     (Source : String;
      Target : String)
      return Boolean
   is
      Move_File_Replace_Existing : constant C_DWord := 16#0000_0001#;

      function Move_File_Ex
        (Existing : System.Address;
         New_Name : System.Address;
         Flags    : C_DWord)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "MoveFileExW";

      Wide_Source : aliased Wide_String := Wide (Source);
      Wide_Target : aliased Wide_String := Wide (Target);
   begin
      return Move_File_Ex
               (Wide_Source'Address,
                Wide_Target'Address,
                Move_File_Replace_Existing) /= 0;
   exception
      when others =>
         return False;
   end Replace_File;

   --  Windows has no readlink: a link is a reparse point. Open it without following it
   --  (FILE_FLAG_OPEN_REPARSE_POINT) and pull the target out of the reparse data. The
   --  print name is the human target ("real.txt"); the substitute name is a fallback.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      use type System.Address;

      Fsctl_Get_Reparse_Point : constant C_DWord := 16#0009_00A8#;
      Open_Existing           : constant C_DWord := 3;
      Flag_Backup_Semantics   : constant C_DWord := 16#0200_0000#;
      Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
      Share_All               : constant C_DWord := 7;
      Tag_Symlink             : constant C_DWord := 16#A000_000C#;
      Tag_Mount_Point         : constant C_DWord := 16#A000_0003#;
      Invalid_Handle          : constant System.Address :=
        System.Storage_Elements.To_Address
          (System.Storage_Elements.Integer_Address'Last);

      function Create_File
        (Name       : System.Address;
         Access_Way : C_DWord;
         Share      : C_DWord;
         Security   : System.Address;
         Creation   : C_DWord;
         Flags      : C_DWord;
         Template   : System.Address)
         return System.Address
        with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

      function Device_Io_Control
        (Handle     : System.Address;
         Code       : C_DWord;
         In_Buffer  : System.Address;
         In_Size    : C_DWord;
         Out_Buffer : System.Address;
         Out_Size   : C_DWord;
         Returned   : access C_DWord;
         Overlapped : System.Address)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "DeviceIoControl";

      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

      Wide_Path : aliased Wide_String := Wide (Path);
      Buffer    : array (0 .. 16 * 1024 - 1) of aliased Interfaces.Unsigned_8 :=
        [others => 0];
      Handle    : System.Address;
      Returned  : aliased C_DWord := 0;
      Outcome   : Interfaces.C.int;
      Ignored   : Interfaces.C.int;

      function U16 (At_Index : Natural) return Natural is
        (Natural (Buffer (At_Index)) + Natural (Buffer (At_Index + 1)) * 256);

      function U32 (At_Index : Natural) return C_DWord is
        (C_DWord (Buffer (At_Index))
         + C_DWord (Buffer (At_Index + 1)) * 256
         + C_DWord (Buffer (At_Index + 2)) * 65_536
         + C_DWord (Buffer (At_Index + 3)) * 16_777_216);
   begin
      Target := Ada.Strings.Unbounded.Null_Unbounded_String;

      Handle := Create_File
        (Name       => Wide_Path'Address,
         Access_Way => 0,
         Share      => Share_All,
         Security   => System.Null_Address,
         Creation   => Open_Existing,
         Flags      => Flag_Backup_Semantics + Flag_Open_Reparse_Point,
         Template   => System.Null_Address);
      if Handle = Invalid_Handle then
         return False;
      end if;

      Outcome := Device_Io_Control
        (Handle     => Handle,
         Code       => Fsctl_Get_Reparse_Point,
         In_Buffer  => System.Null_Address,
         In_Size    => 0,
         Out_Buffer => Buffer'Address,
         Out_Size   => Buffer'Length,
         Returned   => Returned'Access,
         Overlapped => System.Null_Address);
      Ignored := Close_Handle (Handle);
      if Outcome = 0 then
         return False;
      end if;

      declare
         Tag           : constant C_DWord := U32 (0);
         Path_Buf_Base : Natural;
         Name_Off      : Natural;
         Name_Len      : Natural;   --  in bytes
      begin
         if Tag = Tag_Symlink then
            Path_Buf_Base := 20;
         elsif Tag = Tag_Mount_Point then
            Path_Buf_Base := 16;
         else
            return False;
         end if;

         Name_Off := U16 (12);   --  PrintNameOffset
         Name_Len := U16 (14);   --  PrintNameLength
         if Name_Len = 0 then
            Name_Off := U16 (8);    --  SubstituteNameOffset
            Name_Len := U16 (10);   --  SubstituteNameLength
         end if;
         if Name_Len = 0 then
            return False;
         end if;

         declare
            Start  : constant Natural := Path_Buf_Base + Name_Off;
            Chars  : constant Natural := Name_Len / 2;
            Wide_T : Wide_String (1 .. Chars);
         begin
            for Index in 0 .. Chars - 1 loop
               Wide_T (Index + 1) :=
                 Wide_Character'Val (U16 (Start + Index * 2));
            end loop;
            Target := Ada.Strings.Unbounded.To_Unbounded_String
              (Ada.Strings.UTF_Encoding.Wide_Strings.Encode (Wide_T));
         end;
      end;
      return True;
   exception
      when others =>
         return False;
   end Read_Link_Target;

end Hostkit.Fs;
