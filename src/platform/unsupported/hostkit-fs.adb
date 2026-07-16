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

end Hostkit.Fs;
