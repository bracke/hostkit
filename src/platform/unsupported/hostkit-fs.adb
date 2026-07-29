with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

package body Hostkit.Fs is

   --  An unknown host: nothing is claimed, and nothing is pretended.
   function Is_Link (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Is_Link;

   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean
   is
      pragma Unreferenced (Target, Link_Path);
   begin
      return False;
   end Create_Link;

   function Is_Executable (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
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

   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is
      pragma Unreferenced (Target, Link_Path);
   begin
      return False;
   end Create_Hard_Link;

   function Make_Private (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Make_Private;

   function Replace_File
     (Source : String;
      Target : String)
      return Boolean
   is
      pragma Unreferenced (Source, Target);
   begin
      return False;
   end Replace_File;

   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      pragma Unreferenced (Path);
   begin
      Target := Ada.Strings.Unbounded.Null_Unbounded_String;
      return False;
   end Read_Link_Target;

   function Delete_Link (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Delete_Link;

   function Real_Path (Path : String) return String is
      pragma Unreferenced (Path);
   begin
      return "";
   end Real_Path;

   --  No body for this host: say so by saying nothing, rather than guessing at
   --  a layout that may not exist.
   function Own_Executable return String is
   begin
      return "";
   end Own_Executable;

   function Own_Executable_Directory return String is
   begin
      return "";
   end Own_Executable_Directory;

   function Home_Directory return String is
   begin
      if Ada.Environment_Variables.Exists ("HOME") then
         return Ada.Environment_Variables.Value ("HOME");
      end if;
      return "";
   end Home_Directory;

   function Application_Data_Directory return String is
   begin
      return "";
   end Application_Data_Directory;

   function Cache_Directory return String is
   begin
      return "";
   end Cache_Directory;

   function Temp_Directory return String is
   begin
      if Ada.Environment_Variables.Exists ("TMPDIR")
        and then Ada.Environment_Variables.Value ("TMPDIR") /= ""
      then
         return Ada.Environment_Variables.Value ("TMPDIR");
      end if;
      return "/tmp";
   end Temp_Directory;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      --  A host Hostkit has no body for: decline to guess a restriction.
      return False;
   end Uses_Dos_Filename_Rules;

end Hostkit.Fs;
