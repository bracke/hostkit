separate (Hostkit_Suite)
procedure Test_A_Device_File_Names_Its_Own_Device
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Special_File_Kind;
   use type Interfaces.Unsigned_64;
begin
   --  Windows has no device nodes to ask about.
   if Hostkit.Host.Current not in Hostkit.Host.Linux | Hostkit.Host.MacOS then
      Skip ("Test_A_Device_File_Names_Its_Own_Device", "this host has no device nodes");
      return;
   end if;
   declare
      Info : constant Hostkit.Fs.Special_File_Info := Hostkit.Fs.Special_File_Info_Of ("/dev/null");
   begin
      Assert (Info.Available, "the null device is a device file");
      Assert (Info.Kind = Hostkit.Fs.Character_Device, "a character device");
      Assert (Info.Device /= 0, "which stands for a device of its own");
      if Hostkit.Host.Current = Hostkit.Host.Linux then
         --  Major 1, minor 3 in glibc's dev_t encoding: the device the node
         --  stands for (stx_rdev). The volume its node is on (stx_dev, a
         --  devtmpfs) was reported in its place.
         Assert
           (Info.Device = 1 * 256 + 3,
            "/dev/null is device 1,3, not the volume /dev is:" & Interfaces.Unsigned_64'Image (Info.Device));
      end if;
   end;
end Test_A_Device_File_Names_Its_Own_Device;
