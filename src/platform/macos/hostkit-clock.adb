with Interfaces.C;
with System;

package body Hostkit.Clock is
   use type Ada.Calendar.Time;
   use type Interfaces.C.int;

   subtype C_Long is Interfaces.C.long;

   type Timeval is record
      Seconds      : C_Long;
      Microseconds : C_Long;
   end record
     with Convention => C;

   function Settimeofday (Time : access Timeval; Timezone : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "settimeofday";

   function Set_System_Time (Time : Ada.Calendar.Time) return Boolean is
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Elapsed : constant Duration := Time - Epoch;
      Value   : aliased Timeval := (Seconds => C_Long (Long_Long_Integer (Elapsed)), Microseconds => 0);
      Status : Interfaces.C.int;
   begin
      if Elapsed < 0.0 then
         return False;
      end if;

      Status := Settimeofday (Value'Access, System.Null_Address);
      return Status = 0;
   exception
      when others =>
         return False;
   end Set_System_Time;
end Hostkit.Clock;
