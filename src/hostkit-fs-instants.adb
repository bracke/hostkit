with Ada.Calendar.Formatting;
with Ada.Directories;

package body Hostkit.Fs.Instants is
   use type Ada.Calendar.Time;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   Nanoseconds_Per_Second : constant := 1_000_000_000;
   Ticks_Per_Second       : constant := 10_000_000;
   --  From 1601-01-01 to 1970-01-01, in seconds.
   Seconds_From_1601      : constant := 11_644_473_600;

   function Unix_Epoch return Ada.Calendar.Time is
     (Ada.Calendar.Formatting.Time_Of
        (Year => 1970, Month => 1, Day => 1, Seconds => 0.0, Leap_Second => False, Time_Zone => 0));

   function From_Unix
     (Seconds     : Interfaces.Integer_64;
      Nanoseconds : Interfaces.Integer_64)
      return Ada.Calendar.Time
   is
   begin
      --  Duration's small is a nanosecond in GNAT, so both terms are exact.
      return Unix_Epoch + Duration (Seconds) + Duration (Nanoseconds) / Nanoseconds_Per_Second;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         raise Ada.Directories.Use_Error with "the host's file time lies outside Ada.Calendar.Time";
   end From_Unix;

   function From_Filetime (Ticks : Interfaces.Unsigned_64) return Ada.Calendar.Time is
   begin
      if Ticks > Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
         raise Ada.Directories.Use_Error with "the host's file time lies outside Ada.Calendar.Time";
      end if;
      declare
         Since_1970 : constant Interfaces.Integer_64 :=
           Interfaces.Integer_64 (Ticks) - Seconds_From_1601 * Ticks_Per_Second;
         --  mod, not rem: the remainder of an instant before 1970 is still
         --  counted forwards from a whole second.
         Rest       : constant Interfaces.Integer_64 := Since_1970 mod Ticks_Per_Second;
      begin
         return From_Unix
           ((Since_1970 - Rest) / Ticks_Per_Second, Rest * (Nanoseconds_Per_Second / Ticks_Per_Second));
      end;
   end From_Filetime;

end Hostkit.Fs.Instants;
