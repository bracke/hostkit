with Interfaces;

--  A test's way to the saturating counts the POSIX volume-capacity bodies
--  report through, since no filesystem on a runner answers UINT64_MAX on
--  demand the way a FUSE or network mount does. The POSIX hosts bring the
--  body that does it; a host without those bodies says it cannot.
package Hostkit.Saturation_Probe is

   --  Whether this host has the POSIX counts to probe.
   --
   --  @return False where it has none.
   function Available return Boolean;

   --  Blocks of Unit_Size bytes, in bytes, as a volume's capacity is given.
   --
   --  @param Blocks How many blocks.
   --  @param Unit_Size The size of one.
   --  @return The bytes, saturated at Long_Long_Integer'Last.
   function Byte_Count (Blocks, Unit_Size : Interfaces.Unsigned_64) return Long_Long_Integer;

   --  A count, as an inode count is given.
   --
   --  @param Value The host's count.
   --  @return Value, saturated at Long_Long_Integer'Last.
   function Count (Value : Interfaces.Unsigned_64) return Long_Long_Integer;

   --  A count, as a name limit is given.
   --
   --  @param Value The host's count.
   --  @return Value, saturated at Natural'Last.
   function Natural_Count (Value : Interfaces.Unsigned_64) return Natural;

end Hostkit.Saturation_Probe;
