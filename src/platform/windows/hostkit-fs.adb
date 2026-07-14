with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C.Strings;

with System;

package body Hostkit.Fs is

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

end Hostkit.Fs;
