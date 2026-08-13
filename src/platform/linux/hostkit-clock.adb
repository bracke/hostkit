with Ada.Environment_Variables;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Hostkit.Clock is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.Strings.chars_ptr;

   subtype C_Long is Interfaces.C.long;

   type Timeval is record
      Seconds      : C_Long;
      Microseconds : C_Long;
   end record
     with Convention => C;

   function Settimeofday (Time : access Timeval; Timezone : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "settimeofday";

   type Tm is record
      Sec     : Interfaces.C.int;
      Min     : Interfaces.C.int;
      Hour    : Interfaces.C.int;
      Mday    : Interfaces.C.int;
      Mon     : Interfaces.C.int;
      Year    : Interfaces.C.int;
      Wday    : Interfaces.C.int;
      Yday    : Interfaces.C.int;
      Isdst   : Interfaces.C.int;
      Gmtoff  : C_Long;
      Zone    : Interfaces.C.Strings.chars_ptr;
   end record
     with Convention => C;

   function Localtime_R
     (Clock : access C_Long;
      Result : access Tm)
      return access Tm
     with Import, Convention => C, External_Name => "localtime_r";

   procedure Tzset
     with Import, Convention => C, External_Name => "tzset";

   function Resolve_Time_Zone
     (Name : String;
      Time : Ada.Calendar.Time)
      return Time_Zone_Info
   is
      Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Seconds : aliased C_Long;
      Local : aliased Tm;
      Had_TZ : constant Boolean := Ada.Environment_Variables.Exists ("TZ");
      Old_TZ : constant String := (if Had_TZ then Ada.Environment_Variables.Value ("TZ") else "");
      Result : Time_Zone_Info;
   begin
      if Name = "" or else Time < Epoch then
         return Result;
      end if;

      Seconds := C_Long (Long_Long_Integer (Time - Epoch));
      Ada.Environment_Variables.Set ("TZ", Name);
      Tzset;

      if Localtime_R (Seconds'Access, Local'Access) /= null then
         Result.Available := True;
         Result.Offset_Minutes := Integer (Local.Gmtoff / 60);
         if Local.Zone /= Interfaces.C.Strings.Null_Ptr then
            Result.Name := To_Unbounded_String (Interfaces.C.Strings.Value (Local.Zone));
         end if;
      end if;

      if Had_TZ then
         Ada.Environment_Variables.Set ("TZ", Old_TZ);
      else
         Ada.Environment_Variables.Clear ("TZ");
      end if;
      Tzset;
      return Result;
   exception
      when others =>
         if Had_TZ then
            Ada.Environment_Variables.Set ("TZ", Old_TZ);
         else
            Ada.Environment_Variables.Clear ("TZ");
         end if;
         Tzset;
         return (Available => False, Offset_Minutes => 0, Name => Null_Unbounded_String);
   end Resolve_Time_Zone;

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
