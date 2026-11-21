with Hostkit.Posix;

package body Hostkit.Saturation_Probe is

   function Available return Boolean is (True);

   function Byte_Count (Blocks, Unit_Size : Interfaces.Unsigned_64) return Long_Long_Integer is
     (Hostkit.Posix.Saturating_Byte_Count (Blocks, Unit_Size));

   function Count (Value : Interfaces.Unsigned_64) return Long_Long_Integer is
     (Hostkit.Posix.Saturating_Count (Value));

   function Natural_Count (Value : Interfaces.Unsigned_64) return Natural is
     (Hostkit.Posix.Saturating_Natural (Value));

end Hostkit.Saturation_Probe;
