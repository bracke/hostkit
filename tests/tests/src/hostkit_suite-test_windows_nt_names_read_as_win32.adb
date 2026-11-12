with Hostkit.Trash.Recycle_Bin_Format;
separate (Hostkit_Suite)
procedure Test_Windows_Nt_Names_Read_As_Win32
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package WP renames Hostkit.Windows_Paths;
   package Format renames Hostkit.Trash.Recycle_Bin_Format;

   --  Pure text, so checked on every host.
   procedure Check (Name : String; Expected : String; What : String) is
   begin
      Assert
        (WP.Win32_Form (Name) = Expected,
         What & ": " & Name & " read as " & WP.Win32_Form (Name) & ", not " & Expected);
   end Check;
begin
   --  A drive and a share have a plain form, which is what Win32 text carries.
   Check ("\??\C:\x", "C:\x", "a link's NT substitute name on a drive");
   Check ("\\?\C:\x", "C:\x", "a long path on a drive");
   Check ("\??\d:", "d:", "a drive alone");
   Check ("\??\UNC\server\share\x", "\\server\share\x", "an NT share name");
   Check ("\\?\UNC\server\share", "\\server\share", "a long share path");
   Check ("\\?\unc\server\share", "\\server\share", "UNC in any case");

   --  A volume with no drive letter has none: stripping the prefix left the
   --  relative "Volume{...}\", which names something else entirely.
   Check ("\??\Volume{0a1b2c3d-0000-0000-0000-100000000000}\", "\\?\Volume{0a1b2c3d-0000-0000-0000-100000000000}\",
          "a volume mount point's substitute name");
   Check ("\\?\Volume{0a1b}\dir\x", "\\?\Volume{0a1b}\dir\x", "a real path on a volume without a letter");
   Check ("\??\GLOBALROOT\Device\HarddiskVolume1\x", "\\?\GLOBALROOT\Device\HarddiskVolume1\x",
          "a device path");
   Check ("\??\UNCX\y", "\\?\UNCX\y", "a name that only starts like UNC");
   Check ("\??\1:\x", "\\?\1:\x", "a digit is no drive");

   --  Text with neither prefix is left as it is.
   Check ("real.txt", "real.txt", "a relative print name");
   Check ("..\up\x", "..\up\x", "a relative path up");
   Check ("C:\plain", "C:\plain", "a plain drive path");
   Check ("\\server\share", "\\server\share", "a plain share");
   Check ("\\.\pipe\x", "\\.\pipe\x", "a device namespace path");
   Check ("\??", "\??", "a prefix cut short");
   Check ("", "", "nothing");

   --  The Recycle Bin's $I record keeps the same rule, not a copy of it.
   Assert (Format.Without_Long_Prefix ("\\?\C:\x") = "C:\x", "the Recycle Bin reads a long drive path alike");
   Assert
     (Format.Without_Long_Prefix ("\\?\Volume{1}\x") = "\\?\Volume{1}\x",
      "and keeps a volume's prefix alike");
end Test_Windows_Nt_Names_Read_As_Win32;
