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
     & "49 30 8:33 / /media/usb-backup rw - ext4 /dev/sdc1 rw" & LF
     --  A stick labelled "NO NAME": the table writes the space as \040.
     & "50 30 8:49 / /media/u/NO\040NAME rw - vfat /dev/sdd1 rw" & LF
     & "51 30 0:60 / /mnt/share rw - cifs //server/share rw" & LF
     --  An NTFS stick through ntfs-3g: the table says only "fuseblk".
     & "52 30 8:65 / /media/win rw - fuseblk /dev/sde1 rw,user_id=0";
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

   --  A mount point with an escaped space is matched by its real name.
   Assert (FR.Decode_Mount_Field ("/media/u/NO\040NAME") = "/media/u/NO NAME", "\040 decodes to a space");
   Assert (FR.Decode_Mount_Field ("a\134b\011c") = "a\b" & Character'Val (9) & "c",
           "a backslash and a tab decode too");
   Assert (FR.Decode_Mount_Field ("x\9yz\04") = "x\9yz\04", "a backslash without three octal digits is kept");
   Assert
     (FR.Filesystem_Type_For_Mount (Sample, "/media/u/NO NAME/photo.png") = "vfat",
      "a path on a stick whose label holds a space reports the stick's filesystem");

   --  An SMB share folds case but is not DOS-ruled (the client maps the
   --  characters Windows refuses); it and macOS's own volumes count names in
   --  UTF-16 units.
   Assert (FR.Folds_By_Type_Name ("cifs") and then FR.Folds_By_Type_Name ("smb3")
           and then FR.Folds_By_Type_Name ("SMBFS") and then FR.Folds_By_Type_Name ("vfat"),
           "SMB shares and DOS-family volumes fold case");
   Assert (not FR.Folds_By_Type_Name ("ext4") and then not FR.Dos_By_Type_Name ("cifs"),
           "ext4 does not fold case, and a share is not DOS-ruled");
   Assert (FR.Folds_By_Type_Name (FR.Filesystem_Type_For_Mount (Sample, "/mnt/share/x")),
           "a path on a share folds case");
   Assert (FR.Utf16_By_Type_Name ("apfs") and then FR.Utf16_By_Type_Name ("hfs")
           and then FR.Utf16_By_Type_Name ("exfat") and then FR.Utf16_By_Type_Name ("cifs"),
           "APFS, HFS+, DOS-family and SMB volumes count UTF-16 units");
   Assert (not FR.Utf16_By_Type_Name ("ext4") and then not FR.Utf16_By_Type_Name ("nfs")
           and then not FR.Utf16_By_Type_Name (""),
           "ext4, NFS and an unknown volume count bytes");

   --  A FUSE block mount is named by its subtype, else by udev's record of
   --  its device (the mount table's third field); with neither it keeps the
   --  type it has, and so no Windows-family rule.
   Assert (FR.Device_For_Mount (Sample, "/media/win/x.txt") = "8:65",
           "the device of a FUSE block mount is read from its line");
   Assert (FR.Fuse_Block_Type ("fuseblk", "S:disk/by-uuid/1" & LF & "E:ID_FS_TYPE=ntfs" & LF & "E:ID_FS_USAGE=x")
           = "ntfs",
           "udev names the filesystem behind fuseblk");
   Assert (FR.Dos_By_Type_Name
             (FR.Fuse_Block_Type (FR.Filesystem_Type_For_Mount (Sample, "/media/win/x"), "E:ID_FS_TYPE=ntfs")),
           "an ntfs-3g stick is DOS-ruled");
   Assert (FR.Fuse_Block_Type ("fuseblk.ntfs-3g", "") = "ntfs"
           and then FR.Fuse_Block_Type ("fuseblk.exfat-fuse", "") = "exfat",
           "a FUSE subtype names the filesystem");
   Assert (FR.Fuse_Block_Type ("fuseblk", "") = "fuseblk"
           and then not FR.Dos_By_Type_Name (FR.Fuse_Block_Type ("fuseblk", "E:ID_FS_USAGE=filesystem")),
           "an unidentified FUSE block mount assumes no Windows rule");
   Assert (FR.Fuse_Block_Type ("ext4", "E:ID_FS_TYPE=ntfs") = "ext4",
           "only a FUSE block mount asks udev");

   --  The host's own limit for a scratch directory: UTF-16 units on Windows
   --  and macOS (NTFS, APFS), bytes on Linux; 255 of them.
   declare
      use type Hostkit.Fs.Name_Length_Unit;
      Limit : constant Hostkit.Fs.Leaf_Name_Limit := Hostkit.Fs.Leaf_Name_Limit_At (Scratch);
   begin
      Assert (Limit.Most = 255, "a scratch directory holds 255-long names:" & Limit.Most'Image);
      Assert
        ((Limit.Unit = Hostkit.Fs.Utf16_Units) = (Hostkit.Host.Current /= Hostkit.Host.Linux),
         "a scratch directory counts " & Limit.Unit'Image);
   end;

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
