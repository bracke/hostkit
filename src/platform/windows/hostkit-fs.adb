with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C.Strings;

with System;
with System.Storage_Elements;

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

   function Get_Temp_Path
     (Buffer_Length : C_DWord;
      Buffer        : System.Address)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetTempPathA";

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

   --  No mode bits here; see the comment on the file-level answer.
   function Directory_Accessible_By_Others (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Directory_Accessible_By_Others;

   --  No mode bits to set, and this does not write an ACL; see the spec.

   --  None of these exist on this host; see the spec for what each would mean.
   function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean is
      pragma Unreferenced (Path, User, Group);
   begin
      return False;
   end Set_Owner;

   function Set_Extended_Attribute
     (Path  : String;
      Name  : String;
      Value : Ada.Streams.Stream_Element_Array) return Boolean
   is
      pragma Unreferenced (Path, Name, Value);
   begin
      return False;
   end Set_Extended_Attribute;

   function Create_FIFO (Path : String; Mode : Natural) return Boolean is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Create_FIFO;

   function Create_Socket (Path : String; Mode : Natural) return Boolean is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Create_Socket;

   function Special_File_Info_Of (Path : String) return Special_File_Info is
      pragma Unreferenced (Path);
   begin
      return (Available => False, Kind => Not_Special, Device => 0, Mode => 0);
   end Special_File_Info_Of;

   function Create_Device
     (Path   : String;
      Kind   : Device_Kind;
      Device : Interfaces.Unsigned_64;
      Mode   : Natural) return Boolean
   is
      pragma Unreferenced (Path, Kind, Device, Mode);
   begin
      return False;
   end Create_Device;

   --  The one of these Windows does have. NTFS keeps a hard link; FAT does not,
   --  and the call fails there rather than pretending.
   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is
      function Create_Hard_Link_W
        (Link_Name     : System.Address;
         Existing_File : System.Address;
         Attributes    : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "CreateHardLinkW";

      Wide_Target : aliased Wide_String := Wide (Target);
      Wide_Link   : aliased Wide_String := Wide (Link_Path);
      Created     : constant Interfaces.C.int :=
        Create_Hard_Link_W
          (Wide_Link'Address, Wide_Target'Address, System.Null_Address);
   begin
      return Created /= 0;
   exception
      when others =>
         return False;
   end Create_Hard_Link;

   function Make_Private (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Make_Private;

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

   --  Which call removes a link here depends on what the link points at: a link to a
   --  directory carries FILE_ATTRIBUTE_DIRECTORY and only RemoveDirectoryW will take it,
   --  while DeleteFileW takes every other reparse point. Ada.Directories.Delete_File is
   --  DeleteFileW on both platforms, so a directory symlink refused it and came back as
   --  NAME_ERROR "does not exist".
   --
   --  GetFileAttributesW reports the link's own attributes rather than the target's, so
   --  neither the test nor the removal follows the link -- the target is left alone.
   function Delete_Link (Path : String) return Boolean is
      function Remove_Directory (Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "RemoveDirectoryW";

      function Delete_File (Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "DeleteFileW";

      C_Path     : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Attributes : constant C_DWord := Get_File_Attributes (C_Path);
      Wide_Path  : aliased Wide_String := Wide (Path);
   begin
      Interfaces.C.Strings.Free (C_Path);

      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Reparse_Point) = 0
      then
         return False;
      end if;

      if (Attributes and File_Attribute_Directory) /= 0 then
         return Remove_Directory (Wide_Path'Address) /= 0;
      else
         return Delete_File (Wide_Path'Address) /= 0;
      end if;
   exception
      when others =>
         return False;
   end Delete_Link;

   --  Windows has no realpath. Open the path -- following links, so no
   --  FILE_FLAG_OPEN_REPARSE_POINT here -- and ask the kernel for the final, canonical
   --  name of what the handle actually refers to. GetFinalPathNameByHandleW returns it in
   --  the \\?\ (or \\?\UNC\) namespace; strip that prefix so callers see an ordinary path.
   --  Ada.Directories.Full_Name is GetFullPathName here: purely lexical, follows nothing.
   function Real_Path (Path : String) return String is
      use type System.Address;

      Open_Existing         : constant C_DWord := 3;
      Flag_Backup_Semantics : constant C_DWord := 16#0200_0000#;
      Share_All             : constant C_DWord := 7;
      Invalid_Handle        : constant System.Address :=
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

      function Get_Final_Path_Name_By_Handle
        (Handle : System.Address;
         Path   : System.Address;
         Count  : C_DWord;
         Flags  : C_DWord)
         return C_DWord
        with Import => True, Convention => Stdcall,
             External_Name => "GetFinalPathNameByHandleW";

      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

      --  Resolve a single path that must exist, to its canonical long-name form (with
      --  the \\?\ / \\?\UNC\ prefix stripped). Returns "" when Target does not exist.
      function Resolve (Target : String) return String is
         Wide_Path : aliased Wide_String := Wide (Target);
         Wide_Buf  : aliased Wide_String (1 .. 32 * 1024) :=
           [others => Wide_Character'Val (0)];
         Handle    : System.Address;
         Length    : C_DWord;
         Ignored   : Interfaces.C.int;
      begin
         Handle := Create_File
           (Name       => Wide_Path'Address,
            Access_Way => 0,
            Share      => Share_All,
            Security   => System.Null_Address,
            Creation   => Open_Existing,
            Flags      => Flag_Backup_Semantics,
            Template   => System.Null_Address);
         if Handle = Invalid_Handle then
            return "";
         end if;

         --  Flags 0 == VOLUME_NAME_DOS or FILE_NAME_NORMALIZED. Length is the count of
         --  WCHARs written (excluding the terminating NUL); 0 on failure, or -- if it
         --  would not fit -- the required size including the NUL, treated as failure.
         Length := Get_Final_Path_Name_By_Handle
           (Handle => Handle,
            Path   => Wide_Buf'Address,
            Count  => Wide_Buf'Length,
            Flags  => 0);
         Ignored := Close_Handle (Handle);

         if Length = 0 or else Length > Wide_Buf'Length then
            return "";
         end if;

         declare
            Resolved : constant String :=
              Ada.Strings.UTF_Encoding.Wide_Strings.Encode
                (Wide_Buf (1 .. Natural (Length)));
         begin
            --  \\?\UNC\server\share -> \\server\share ; \\?\C:\dir -> C:\dir.
            if Resolved'Length >= 8
              and then Resolved (Resolved'First .. Resolved'First + 7) = "\\?\UNC\"
            then
               return "\\" & Resolved (Resolved'First + 8 .. Resolved'Last);
            elsif Resolved'Length >= 4
              and then Resolved (Resolved'First .. Resolved'First + 3) = "\\?\"
            then
               return Resolved (Resolved'First + 4 .. Resolved'Last);
            else
               return Resolved;
            end if;
         end;
      end Resolve;

      --  Index of the last path separator in S, or 0 if there is none.
      function Last_Separator (S : String) return Natural is
      begin
         for Index in reverse S'Range loop
            if S (Index) = '\' or else S (Index) = '/' then
               return Index;
            end if;
         end loop;
         return 0;
      end Last_Separator;

      --  Re-attach a nonexistent leaf onto its resolved parent, so a path that does not
      --  exist still lands in the same long-name form as the roots it is compared against.
      function Parent_Compose (P : String) return String is
         Cut : constant Natural := Last_Separator (P);
      begin
         if Cut > P'First then
            declare
               Parent : constant String := Resolve (P (P'First .. Cut - 1));
            begin
               if Parent /= "" then
                  return Parent & "\" & P (Cut + 1 .. P'Last);
               end if;
            end;
         end if;
         return "";
      end Parent_Compose;

      --  Canonicalize P, following symbolic links even when their target does not exist.
      --  GetFinalPathNameByHandleW resolves an existing path directly; when it cannot
      --  (a broken or cyclic link) and P is itself a link, read the link's own target and
      --  resolve THAT -- matching POSIX, where Full_Name resolves a link to its target
      --  path even if the target is missing. Without this a broken-link input root stayed
      --  the link's own path while the followed target became a sibling, so the scanner's
      --  containment check read them as unrelated (SCAN_SYMLINK_TARGET_OUTSIDE_INPUT). A
      --  link cycle collapses to the lexically-smallest path in the chain, so every member
      --  maps to one representative and the scanner detects the revisit as a cycle.
      function Resolve_Chain
        (P : String; Depth : Natural; Min_So_Far : String) return String
      is
         Direct  : constant String := Resolve (P);
         New_Min : constant String :=
           (if Min_So_Far = "" or else P < Min_So_Far then P else Min_So_Far);
      begin
         if Direct /= "" then
            return Direct;
         end if;
         if Is_Link (P) then
            if Depth = 0 then
               return Parent_Compose (New_Min);
            end if;
            declare
               Target : Ada.Strings.Unbounded.Unbounded_String;
            begin
               if Read_Link_Target (P, Target) then
                  declare
                     T   : constant String :=
                       Ada.Strings.Unbounded.To_String (Target);
                     Cut : constant Natural := Last_Separator (P);
                     Abs_Target : constant String :=
                       (if T'Length >= 1
                          and then (T (T'First) = '\' or else T (T'First) = '/')
                        then T
                        elsif T'Length >= 2 and then T (T'First + 1) = ':'
                        then T
                        elsif Cut > P'First
                        then P (P'First .. Cut - 1) & "/" & T
                        else T);
                  begin
                     return Resolve_Chain (Abs_Target, Depth - 1, New_Min);
                  end;
               end if;
            end;
         end if;
         return Parent_Compose (P);
      end Resolve_Chain;
   begin
      return Resolve_Chain (Path, 40, "");
   exception
      when others =>
         return "";
   end Real_Path;

   --  The directory part of a Windows path, either separator.
   function Directory_Part (Path : String) return String is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '\' or else Path (Index) = '/' then
            return Path (Path'First .. Index - 1);
         end if;
      end loop;
      return "";
   end Directory_Part;

   --  GetModuleFileNameW with a null module is this program's own image path.
   --  Wide, because a user profile with a non-Latin-1 name is ordinary here and
   --  the ANSI call would mangle it.
   function Own_Executable return String is
      function Get_Module_File_Name
        (Module : System.Address;
         Buffer : System.Address;
         Size   : C_DWord)
         return C_DWord
        with Import => True, Convention => Stdcall,
             External_Name => "GetModuleFileNameW";

      Buffer : aliased Wide_String (1 .. 32768) := [others => Wide_Character'Val (0)];
      Length : constant C_DWord :=
        Get_Module_File_Name
          (System.Null_Address, Buffer'Address, C_DWord (Buffer'Length));
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      if Length = 0 or else Length >= C_DWord (Buffer'Length) then
         return "";
      end if;

      for Index in 1 .. Natural (Length) loop
         exit when Buffer (Index) = Wide_Character'Val (0);
         if Wide_Character'Pos (Buffer (Index)) <= Character'Pos (Character'Last) then
            Ada.Strings.Unbounded.Append
              (Result, Character'Val (Wide_Character'Pos (Buffer (Index))));
         end if;
      end loop;

      return Ada.Strings.Unbounded.To_String (Result);
   exception
      when others =>
         return "";
   end Own_Executable;

   function Own_Executable_Directory return String is
      Own : constant String := Own_Executable;
   begin
      return (if Own = "" then "" else Directory_Part (Own));
   end Own_Executable_Directory;

   --  USERPROFILE is the profile folder, and HOMEDRIVE+HOMEPATH is what a
   --  domain login sets instead. HOME exists only where something POSIX-shaped
   --  put it there, which is why it is last rather than first.
   function Home_Directory return String is
      function Env (Name : String) return String is
        (if Ada.Environment_Variables.Exists (Name)
         then Ada.Environment_Variables.Value (Name)
         else "");
   begin
      if Env ("USERPROFILE") /= "" then
         return Env ("USERPROFILE");
      elsif Env ("HOMEDRIVE") /= "" and then Env ("HOMEPATH") /= "" then
         return Env ("HOMEDRIVE") & Env ("HOMEPATH");
      else
         return Env ("HOME");
      end if;
   end Home_Directory;

   function Application_Data_Directory return String is
      Home : constant String := Home_Directory;
   begin
      if Ada.Environment_Variables.Exists ("APPDATA")
        and then Ada.Environment_Variables.Value ("APPDATA") /= ""
      then
         return Ada.Environment_Variables.Value ("APPDATA");
      end if;
      return (if Home = "" then "" else Home & "\AppData\Roaming");
   end Application_Data_Directory;

   function Cache_Directory return String is
      Home : constant String := Home_Directory;
   begin
      --  LOCALAPPDATA, the non-roaming half of the profile. See the spec.
      if Ada.Environment_Variables.Exists ("LOCALAPPDATA")
        and then Ada.Environment_Variables.Value ("LOCALAPPDATA") /= ""
      then
         return Ada.Environment_Variables.Value ("LOCALAPPDATA");
      end if;
      return (if Home = "" then "" else Home & "\AppData\Local");
   end Cache_Directory;

   --  The same place as the application data, and roaming on purpose: what the
   --  user chose should follow them to another machine.
   function Config_Directory return String is
   begin
      return Application_Data_Directory;
   end Config_Directory;

   function Temp_Directory return String is
      use type Interfaces.C.size_t;
      Buf : Interfaces.C.char_array (0 .. 519) := (others => Interfaces.C.nul);
      N   : constant C_DWord := Get_Temp_Path (C_DWord (Buf'Length), Buf'Address);
   begin
      --  GetTempPathA returns 0 on failure, or the length required if the
      --  buffer was too small; 520 bytes comfortably holds any MAX_PATH temp dir.
      if N = 0 or else N > C_DWord (Buf'Length) then
         return ".";
      end if;
      declare
         Raw : constant String :=
           Interfaces.C.To_Ada (Buf (0 .. Interfaces.C.size_t (N) - 1), Trim_Nul => False);
      begin
         --  GetTempPathA always appends a trailing backslash; drop it so the
         --  result composes with "/" or "\" the way callers expect.
         if Raw'Length > 1 and then (Raw (Raw'Last) = '\' or else Raw (Raw'Last) = '/') then
            return Raw (Raw'First .. Raw'Last - 1);
         end if;
         return Raw;
      end;
   end Temp_Directory;

   function Create_Temporary_Directory (Prefix : String) return String is
      Base : constant String := Temp_Directory;

      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left));

      function Time_Image return String is
         Raw : constant String := Duration'Image (Ada.Calendar.Seconds (Ada.Calendar.Clock));
         Result : String := Raw;
      begin
         for C of Result loop
            if C = ' ' or else C = '.' then
               C := '-';
            end if;
         end loop;
         return Result;
      end Time_Image;

      function Safe_Prefix return String is
         Result : String := Prefix;
      begin
         for C of Result loop
            if not (C in 'A' .. 'Z' or else C in 'a' .. 'z'
                    or else C in '0' .. '9' or else C = '-' or else C = '_')
            then
               C := '-';
            end if;
         end loop;
         return (if Result = "" then "hostkit-temp" else Result);
      end Safe_Prefix;
   begin
      for Attempt in 1 .. 1000 loop
         declare
            Candidate : constant String :=
              Ada.Directories.Compose
                (Containing_Directory => Base,
                 Name => Safe_Prefix & "-" & Time_Image & "-" & Image (Attempt));
         begin
            Ada.Directories.Create_Directory (Candidate);
            return Candidate;
         exception
            when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
               null;
         end;
      end loop;
      return "";
   end Create_Temporary_Directory;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      --  Every local Windows volume is a DOS-family filesystem (NTFS, FAT,
      --  exFAT); a POSIX filesystem there needs a third-party driver and is
      --  vanishingly rare. Treat them all as DOS-ruled, which is also exactly the
      --  host-based behaviour this refines on the other platforms.
      return True;
   end Uses_Dos_Filename_Rules;

   ---------------
   -- Separator --
   ---------------

   --  Written as a backslash. Both are accepted by the file calls, which is
   --  why a path built with the wrong one goes unnoticed until it is shown
   --  to someone.
   --
   --  One backslash. Ada string and character literals carry no escapes, so
   --  a doubled one here is two characters where one is meant -- and in a
   --  character literal it is not a literal at all, which is what stopped
   --  every Windows build of this crate.
   function Separator return Character is ('\');

   ---------------------------
   -- Search_Path_Delimiter --
   ---------------------------

   function Search_Path_Delimiter return Character is
   begin
      return ';';
   end Search_Path_Delimiter;

   ------------------------
   -- Executable_Suffix --
   ------------------------

   function Executable_Suffix return String is
   begin
      return ".exe";
   end Executable_Suffix;

   -----------------------------------
   -- Starts_Without_An_Interpreter --
   -----------------------------------

   --  What the loader starts, which is not what the host calls a program. A
   --  .bat and a .cmd are read by the command interpreter, a .ps1 by another
   --  shell again, an .msi by the installer -- CreateProcess starts none of
   --  them, and answering True here would send a consumer to a failure that
   --  looks like the file being missing.
   function Starts_Without_An_Interpreter (Path : String) return Boolean is
      function Ends_With (Suffix : String) return Boolean
      is (Path'Length >= Suffix'Length
          and then Ada.Characters.Handling.To_Lower
                     (Path (Path'Last - Suffix'Length + 1 .. Path'Last))
                   = Suffix);
   begin
      return Is_Executable (Path)
        and then (Ends_With (".exe") or else Ends_With (".com"));
   end Starts_Without_An_Interpreter;

end Hostkit.Fs;
