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

end Hostkit.Fs;
