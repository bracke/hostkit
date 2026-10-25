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
