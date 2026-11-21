with Interfaces;
with Hostkit.Saturation_Probe;
separate (Hostkit_Suite)
procedure Test_A_Volume_Count_Saturates
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package Probe renames Hostkit.Saturation_Probe;
   use type Interfaces.Unsigned_64;
   Uncounted : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last;
begin
   if not Probe.Available then
      Skip ("Test_A_Volume_Count_Saturates", "this host has no POSIX volume counts");
      return;
   end if;
   --  What a FUSE or network filesystem answers for what it does not count.
   Assert (Probe.Byte_Count (Uncounted, 4_096) = Long_Long_Integer'Last,
           "UINT64_MAX blocks is the largest byte count, not an overflow");
   Assert (Probe.Byte_Count (2 ** 52, 4_096) = Long_Long_Integer'Last,
           "a product past the largest count saturates");
   Assert (Probe.Byte_Count (2 ** 40, 4_096) = 2 ** 52, "a product that fits is exact");
   Assert (Probe.Byte_Count (0, 4_096) = 0 and then Probe.Byte_Count (Uncounted, 0) = 0,
           "no blocks, or blocks of no size, are no bytes");
   Assert (Probe.Count (Uncounted) = Long_Long_Integer'Last, "UINT64_MAX inodes saturates");
   Assert (Probe.Count (12_345) = 12_345, "a count that fits is exact");
   Assert (Probe.Natural_Count (Uncounted) = Natural'Last, "UINT64_MAX as a name limit saturates");
   Assert (Probe.Natural_Count (255) = 255, "a name limit that fits is exact");
end Test_A_Volume_Count_Saturates;
