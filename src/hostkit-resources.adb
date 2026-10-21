with Ada.Directories;

with Hostkit.Fs;

package body Hostkit.Resources is

   function Beside_Executable
     (Relative_Path : String;
      Levels        : Natural := 2)
      return String
   is
      function Search (Base : String; Remaining : Natural) return String is
         Candidate : constant String := Hostkit.Fs.Join (Base, Relative_Path);
      begin
         if Ada.Directories.Exists (Candidate) then
            return Ada.Directories.Full_Name (Candidate);
         elsif Remaining = 0 then
            return "";
         end if;

         declare
            Parent : constant String := Ada.Directories.Containing_Directory (Base);
         begin
            return (if Parent = Base then "" else Search (Parent, Remaining - 1));
         end;
      exception
         when Ada.Directories.Use_Error | Ada.Directories.Name_Error =>
            return "";
      end Search;

      Directory : constant String := Hostkit.Fs.Own_Executable_Directory;
   begin
      return (if Directory = "" or else Relative_Path = "" then "" else Search (Directory, Levels));
   end Beside_Executable;

end Hostkit.Resources;
