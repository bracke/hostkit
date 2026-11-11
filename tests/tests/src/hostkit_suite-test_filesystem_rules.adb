separate (Hostkit_Suite)
procedure Test_Filesystem_Rules (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   package FR renames Hostkit.Filesystem_Rules;

   LF     : constant Character := Character'Val (10);
   --  A miniature /proc/self/mountinfo: an ext4 root, a FAT stick under
   --  /media/usb, and an ext4 disk under /media/usb-backup whose mount point
   --  merely starts with the same text.
   Sample : constant String :=
     "30 1 8:2 / / rw,relatime - ext4 /dev/sda2 rw" & LF
     & "48 30 8:17 / /media/usb rw,nosuid - vfat /dev/sdb1 rw,fmask=0022" & LF
     & "49 30 8:33 / /media/usb-backup rw - ext4 /dev/sdc1 rw";
begin
   --  The type classification is pure and matched case-insensitively.
   Assert (FR.Dos_By_Type_Name ("vfat"), "vfat is a DOS-ruled filesystem");
   Assert (FR.Dos_By_Type_Name ("exfat") and then FR.Dos_By_Type_Name ("ntfs"),
           "exfat and ntfs are DOS-ruled");
   Assert (FR.Dos_By_Type_Name ("FAT32") and then FR.Dos_By_Type_Name ("NTFS"),
           "the classifier is case-insensitive");
   Assert (not FR.Dos_By_Type_Name ("ext4"), "ext4 is not DOS-ruled");
   Assert (not FR.Dos_By_Type_Name ("apfs") and then not FR.Dos_By_Type_Name ("btrfs"),
           "apfs and btrfs are not DOS-ruled");
   Assert (not FR.Dos_By_Type_Name (""), "an unknown filesystem is not DOS-ruled");

   --  The deepest covering mount wins, and a sibling that merely shares a
   --  prefix (/media/usb-backup vs /media/usb) does not match.
   Assert
     (FR.Filesystem_Type_For_Mount (Sample, "/home/user/doc.txt") = "ext4",
      "a path under the root mount reports the root filesystem");
   Assert
     (FR.Filesystem_Type_For_Mount (Sample, "/media/usb/photo.png") = "vfat",
      "a path under a deeper mount reports that mount's filesystem");
   Assert
     (FR.Filesystem_Type_For_Mount (Sample, "/media/usb-backup/x") = "ext4",
      "a sibling mount sharing a name prefix is not matched");
   Assert
     (FR.Dos_By_Type_Name (FR.Filesystem_Type_For_Mount (Sample, "/media/usb/x")),
      "a file destined for the FAT stick is judged DOS-ruled");

   --  The host query answers, and agrees with the host: a POSIX scratch
   --  directory is not DOS-ruled, while every Windows volume is.
   if Hostkit.Shell.Is_Command_Shell then
      Assert (Hostkit.Fs.Uses_Dos_Filename_Rules (Scratch),
              "Windows treats its volumes as DOS-ruled");
   else
      Assert (not Hostkit.Fs.Uses_Dos_Filename_Rules (Scratch),
              "a POSIX scratch directory is not DOS-ruled");
   end if;
   Assert
     (not Hostkit.Fs.Uses_Dos_Filename_Rules ("") or else Hostkit.Shell.Is_Command_Shell,
      "an unresolvable path answers without raising");
end Test_Filesystem_Rules;
