with Ada.Calendar;
with Ada.Strings.Unbounded;

package body Hostkit.Clock is
   function Resolve_Time_Zone
     (Name : String;
      Time : Ada.Calendar.Time)
      return Time_Zone_Info
   is
      pragma Unreferenced (Name, Time);
   begin
      return (Available => False, Offset_Minutes => 0, Name => Ada.Strings.Unbounded.Null_Unbounded_String);
   end Resolve_Time_Zone;

   function Set_System_Time (Time : Ada.Calendar.Time) return Boolean is
      pragma Unreferenced (Time);
   begin
      return False;
   end Set_System_Time;
end Hostkit.Clock;
