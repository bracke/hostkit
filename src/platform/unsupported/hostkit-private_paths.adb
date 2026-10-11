package body Hostkit.Private_Paths is
   function Create_Directory (Path : String) return Create_Outcome is
      pragma Unreferenced (Path);
   begin
      return Create_Error;
   end Create_Directory;

   function Ensure_Directory (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Ensure_Directory;

   function Restrict_Open_File (Descriptor : Integer) return Boolean is
      pragma Unreferenced (Descriptor);
   begin
      return False;
   end Restrict_Open_File;
end Hostkit.Private_Paths;
