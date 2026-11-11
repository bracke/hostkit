with Ada.Calendar;
with Interfaces;

--  A host's file time as an Ada.Calendar.Time: the arithmetic the host
--  bodies of Modification_Time_Of share, written once.
--
--  Both forms count from an instant in UTC, so both are read against an
--  epoch made with Ada.Calendar.Formatting.Time_Of (..., Time_Zone => 0).
--  Ada.Calendar.Time_Of and GNAT.OS_Lib.GM_Time_Of read their fields as
--  local time, which shifts the answer by the zone's offset.
private package Hostkit.Fs.Instants is

   --  @param Seconds Seconds since 1970-01-01 00:00:00 UTC (POSIX st_mtime).
   --  @param Nanoseconds Nanoseconds past them, 0 .. 999_999_999.
   --  @return That instant.
   --  @exception Ada.Directories.Use_Error The instant lies outside
   --    Ada.Calendar.Time (before 1901, or after 2262 where Duration ends).
   function From_Unix
     (Seconds     : Interfaces.Integer_64;
      Nanoseconds : Interfaces.Integer_64)
      return Ada.Calendar.Time;

   --  @param Ticks A Windows FILETIME: 100 ns ticks since 1601-01-01 UTC.
   --  @return That instant.
   --  @exception Ada.Directories.Use_Error As for From_Unix.
   function From_Filetime (Ticks : Interfaces.Unsigned_64) return Ada.Calendar.Time;

end Hostkit.Fs.Instants;
