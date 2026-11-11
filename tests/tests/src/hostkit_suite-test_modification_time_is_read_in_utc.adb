with Ada.Calendar.Formatting;

separate (Hostkit_Suite)
procedure Test_Modification_Time_Is_Read_In_UTC
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Calendar.Time;
   use type Interfaces.Integer_64;
   File      : constant String := Ada.Directories.Compose (Scratch, "hk-utc-time.txt");
   Windows   : constant Boolean := Hostkit.Host.Current = Hostkit.Host.Windows;
   Had_Zone  : constant Boolean := Ada.Environment_Variables.Exists ("TZ");
   Old_Zone  : constant String := (if Had_Zone then Ada.Environment_Variables.Value ("TZ") else "");
   Times     : Hostkit.Metadata_Copy.Entry_Times;

   procedure Restore_Zone is
   begin
      if Had_Zone then
         Ada.Environment_Variables.Set ("TZ", Old_Zone);
      else
         Ada.Environment_Variables.Clear ("TZ");
      end if;
   end Restore_Zone;

   --  Set File's modification time to Seconds and Nanoseconds past
   --  1970-01-01 UTC (a multiple of 100 ns, which Windows can hold) in the
   --  host's own form, and read it back while the local zone is far from
   --  UTC: it must be that instant, made in UTC.
   procedure Expect
     (Seconds     : Interfaces.Integer_64;
      Nanoseconds : Interfaces.Integer_64;
      Instant     : Ada.Calendar.Time;
      What        : String)
   is
      Ticks_From_1601 : constant Interfaces.Integer_64 :=
        (Seconds + 11_644_473_600) * 10_000_000 + Nanoseconds / 100;
   begin
      if Windows then
         Times (3) := Ticks_From_1601;
         Times (4) := 0;
      else
         Times (3) := Seconds;
         Times (4) := Nanoseconds;
      end if;
      Assert (Hostkit.Metadata_Copy.Apply_Times (File, Times), What & ": the time is set");
      --  Thirteen hours east of UTC, so local time is never UTC here.
      Ada.Environment_Variables.Set ("TZ", "XST-13");
      Assert (Hostkit.Fs.Modification_Time_Of (File) = Instant, What & ": it reads back as that instant");
      if not Windows then
         Assert
           (Hostkit.Fs.Modification_Time_Of (File) = Ada.Directories.Modification_Time (File),
            What & ": as Ada.Directories reads it");
      end if;
      Restore_Zone;
   end Expect;
begin
   Write_File (File, "utc");
   Assert (Hostkit.Metadata_Copy.Capture_Times (File, Times), "the file's times are read");
   begin
      --  2001-09-09 01:46:40 UTC is 1_000_000_000 seconds past the epoch.
      Expect
        (1_000_000_000, 123_456_700,
         Ada.Calendar.Formatting.Time_Of
           (Year => 2001, Month => 9, Day => 9, Hour => 1, Minute => 46, Second => 40, Sub_Second => 0.1234567,
            Leap_Second => False, Time_Zone => 0),
         "a time in 2001");
      --  Half a second before the epoch: the whole seconds count down, the
      --  fraction still up.
      Expect
        (-1, 500_000_000,
         Ada.Calendar.Formatting.Time_Of
           (Year => 1969, Month => 12, Day => 31, Hour => 23, Minute => 59, Second => 59, Sub_Second => 0.5,
            Leap_Second => False, Time_Zone => 0),
         "a time before 1970");
   exception
      when others =>
         Restore_Zone;
         raise;
   end;
   Ada.Directories.Delete_File (File);
end Test_Modification_Time_Is_Read_In_UTC;
