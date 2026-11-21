package body Hostkit.Saturation_Probe is

   function Available return Boolean is (False);

   function Byte_Count (Blocks, Unit_Size : Interfaces.Unsigned_64) return Long_Long_Integer is
      pragma Unreferenced (Blocks, Unit_Size);
   begin
      return 0;
   end Byte_Count;

   function Count (Value : Interfaces.Unsigned_64) return Long_Long_Integer is
      pragma Unreferenced (Value);
   begin
      return 0;
   end Count;

   function Natural_Count (Value : Interfaces.Unsigned_64) return Natural is
      pragma Unreferenced (Value);
   begin
      return 0;
   end Natural_Count;

end Hostkit.Saturation_Probe;
