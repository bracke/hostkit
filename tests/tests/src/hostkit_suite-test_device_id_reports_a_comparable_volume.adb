separate (Hostkit_Suite)
procedure Test_Device_Id_Reports_A_Comparable_Volume
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   First            : constant String := Ada.Directories.Compose (Scratch, "hk-device-first");
   Second           : constant String := Ada.Directories.Compose (Scratch, "hk-device-second");
   Missing          : constant String := Ada.Directories.Compose (Scratch, "hk-device-missing");
   First_Available  : Boolean;
   Second_Available : Boolean;
   Missing_Available : Boolean;
   First_Device     : Long_Long_Integer;
   Second_Device    : Long_Long_Integer;
   Missing_Device   : Long_Long_Integer;
   pragma Unreferenced (Missing_Device);

   procedure Remove (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Remove;
begin
   Remove (First);
   Remove (Second);
   Remove (Missing);

   Write_File (First, "first");
   Write_File (Second, "second");

   First_Device := Hostkit.Metadata.Device_Id (First, First_Available);
   Second_Device := Hostkit.Metadata.Device_Id (Second, Second_Available);
   Missing_Device := Hostkit.Metadata.Device_Id (Missing, Missing_Available);

   Assert (not Missing_Available, "a missing file has no device id to report");

   if First_Available or else Second_Available then
      Assert (First_Available, "device id availability is stable for sibling files");
      Assert (Second_Available, "device id availability is stable for sibling files");
      Assert (First_Device = Second_Device, "sibling files report the same device id");
   end if;

   --  Equal ids for siblings also hold when every id is the same constant,
   --  which is how reading the wrong statx pair (the device a special file
   --  stands for, zero for files) went unnoticed. On Linux a file's volume
   --  is never zero, and /proc is always a filesystem of its own.
   if Hostkit.Host.Current = Hostkit.Host.Linux then
      declare
         Proc_Available : Boolean;
         Proc_Device    : constant Long_Long_Integer := Hostkit.Metadata.Device_Id ("/proc", Proc_Available);
      begin
         Assert (First_Available and then First_Device /= 0, "a file reports the volume that holds it");
         Assert
           (Proc_Available and then Proc_Device /= First_Device,
            "files on different filesystems report different device ids");
      end;
   end if;

   Ada.Directories.Delete_File (First);
   Ada.Directories.Delete_File (Second);
end Test_Device_Id_Reports_A_Comparable_Volume;
