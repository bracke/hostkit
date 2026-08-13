with Ada.Calendar;
with Ada.Strings.Unbounded;

package Hostkit.Clock is
   type Time_Zone_Info is record
      Available      : Boolean := False;
      Offset_Minutes : Integer := 0;
      Name           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Resolve_Time_Zone
     (Name : String;
      Time : Ada.Calendar.Time)
      return Time_Zone_Info;

   function Set_System_Time (Time : Ada.Calendar.Time) return Boolean;
end Hostkit.Clock;
