with Ada.Calendar.Formatting;
with Interfaces.C;

package body Hostkit.Clock is
   use type Interfaces.C.int;

   type Word is mod 2 ** 16
     with Convention => C;

   type Systemtime is record
      Year         : Word;
      Month        : Word;
      Day_Of_Week  : Word;
      Day          : Word;
      Hour         : Word;
      Minute       : Word;
      Second       : Word;
      Milliseconds : Word;
   end record
     with Convention => C;

   function SetSystemTime (Time : access constant Systemtime) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "SetSystemTime";

   function Set_System_Time (Time : Ada.Calendar.Time) return Boolean is
      Year       : Ada.Calendar.Year_Number;
      Month      : Ada.Calendar.Month_Number;
      Day        : Ada.Calendar.Day_Number;
      Hour       : Ada.Calendar.Formatting.Hour_Number;
      Minute     : Ada.Calendar.Formatting.Minute_Number;
      Second     : Ada.Calendar.Formatting.Second_Number;
      Sub_Second : Ada.Calendar.Formatting.Second_Duration;
      Value      : aliased Systemtime;
   begin
      Ada.Calendar.Formatting.Split
        (Time, Year, Month, Day, Hour, Minute, Second, Sub_Second, Time_Zone => 0);
      Value :=
        (Year => Word (Year),
         Month => Word (Month),
         Day_Of_Week => 0,
         Day => Word (Day),
         Hour => Word (Hour),
         Minute => Word (Minute),
         Second => Word (Second),
         Milliseconds => Word (Long_Long_Integer (Sub_Second * 1_000.0)));
      return SetSystemTime (Value'Access) /= 0;
   exception
      when others =>
         return False;
   end Set_System_Time;
end Hostkit.Clock;
