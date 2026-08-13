with Ada.Calendar;

package Hostkit.Clock is
   function Set_System_Time (Time : Ada.Calendar.Time) return Boolean;
end Hostkit.Clock;
