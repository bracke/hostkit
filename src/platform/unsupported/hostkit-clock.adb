package body Hostkit.Clock is
   function Set_System_Time (Time : Ada.Calendar.Time) return Boolean is
      pragma Unreferenced (Time);
   begin
      return False;
   end Set_System_Time;
end Hostkit.Clock;
