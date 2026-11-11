package body Hostkit.Regular_Files is
   function Open_Read
     (Path         : String;
      Follow_Links : Boolean;
      Supported    : out Boolean) return GNAT.OS_Lib.File_Descriptor
   is
      pragma Unreferenced (Path, Follow_Links);
   begin
      Supported := False;
      return GNAT.OS_Lib.Invalid_FD;
   end Open_Read;

   --  No host call to make: GNAT's own, with its path limit and its mode.
   function Create_New
     (Path      : String;
      Mode      : Natural := 8#644#;
      Encrypted : Boolean := False) return GNAT.OS_Lib.File_Descriptor
   is
      pragma Unreferenced (Mode, Encrypted);
   begin
      return GNAT.OS_Lib.Create_New_File (Path, GNAT.OS_Lib.Binary);
   exception
      when others =>
         return GNAT.OS_Lib.Invalid_FD;
   end Create_New;

   function Skip_Zeros
     (Descriptor : GNAT.OS_Lib.File_Descriptor;
      Count      : Integer) return Boolean
   is
      pragma Unreferenced (Descriptor, Count);
   begin
      return False;
   end Skip_Zeros;

   function Finish_Sparse (Descriptor : GNAT.OS_Lib.File_Descriptor) return Boolean is
      pragma Unreferenced (Descriptor);
   begin
      return False;
   end Finish_Sparse;
end Hostkit.Regular_Files;
