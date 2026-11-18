--  Which filesystems enforce DOS/Windows filename rules, decided from the
--  identifiers the hosts report.
--
--  A name that is fine on one filesystem is illegal on another: ext4 and APFS
--  allow any byte but '/' and NUL, while FAT, exFAT and NTFS forbid \ : < > " |
--  ? *, the reserved device names and a trailing dot, and fold case. A file
--  manager that validates a new name has to ask about the *destination*
--  filesystem, not the host it runs on -- a colon is fine in a name on a Linux
--  ext4 disk but not on the FAT USB stick plugged into the same machine.
--
--  These are pure lookups over the type identifiers a mount table or a volume
--  query reports, kept out of the per-OS bodies so they can be exercised on any
--  platform.
package Hostkit.Filesystem_Rules is

   --  Does a filesystem of this type enforce DOS/Windows filename rules? Name is
   --  a type identifier as the host reports it -- "vfat", "exfat", "ntfs",
   --  "msdos" from a Linux mount table, "FAT32"/"NTFS"/"exFAT" from a Windows or
   --  macOS volume query -- matched case-insensitively. Anything unrecognised
   --  (an ext/btrfs/xfs/apfs/hfs filesystem, or an empty string) answers False.
   function Dos_By_Type_Name (Name : String) return Boolean;

   --  Does a filesystem of this type take two names that differ only in case
   --  for the same file? The DOS-ruled types (Dos_By_Type_Name), and an SMB
   --  share -- "cifs" or "smb3" from a Linux mount table, "smbfs" from macOS
   --  -- whose server, Windows or Samba as it is set up by default, compares
   --  names that way. Matched case-insensitively; anything else answers False.
   --  An SMB share is not DOS-ruled: Linux and macOS map the characters
   --  Windows refuses onto ones it keeps (mapposix, SFM), so a colon is
   --  stored there.
   function Folds_By_Type_Name (Name : String) return Boolean;

   --  Does a filesystem of this type measure a name's length in UTF-16 units
   --  rather than in bytes? The DOS-ruled types and the SMB shares (Windows
   --  names are UTF-16 on the wire and on the disk behind it), and macOS's
   --  own "apfs" and "hfs", which hold 255 UTF-16 units however many bytes
   --  their UTF-8 takes. Matched case-insensitively; anything else (ext4,
   --  btrfs, xfs, nfs, an empty string) measures bytes.
   function Utf16_By_Type_Name (Name : String) return Boolean;

   --  A field of a Linux mount table (/proc/mounts, /proc/self/mountinfo)
   --  with its octal escapes decoded: the table writes a space, tab, newline
   --  or backslash in a mount point as \040, \011, \012 or \134, so
   --  "/media/u/NO\040NAME" is the mount point "/media/u/NO NAME". A
   --  backslash not followed by three octal digits is kept as it is.
   function Decode_Mount_Field (Value : String) return String;

   --  The filesystem type of the deepest mount point that contains Target_Path,
   --  read out of the contents of a Linux /proc/self/mountinfo file, its mount
   --  points decoded (Decode_Mount_Field). Empty when
   --  no mount line covers the path (which cannot normally happen, since "/"
   --  always does) or the text cannot be parsed.
   function Filesystem_Type_For_Mount
     (Mountinfo   : String;
      Target_Path : String)
      return String;

   --  The block device ("major:minor", the mount table's third field) of the
   --  deepest mount point that contains Target_Path, read as
   --  Filesystem_Type_For_Mount reads its type. Empty when no line covers it.
   function Device_For_Mount
     (Mountinfo   : String;
      Target_Path : String)
      return String;

   --  The filesystem behind a FUSE block mount, which the mount table names
   --  only "fuseblk": ntfs-3g and exfat-fuse both mount that way, and both
   --  keep Windows-family names. Fs_Type is the type field; a subtype the
   --  mount carries ("fuseblk.ntfs-3g") names it, and failing that
   --  Udev_Record -- the text of /run/udev/data/b<major>:<minor>, which udev
   --  keeps readable to every user and fills from the volume's own superblock
   --  -- does, through its "E:ID_FS_TYPE=" line. Anything that is not a FUSE
   --  block type is returned as it is.
   --
   --  @param Fs_Type The mount table's type field.
   --  @param Udev_Record udev's record of the mount's device, or "".
   --  @return "ntfs", "exfat", "vfat" or what udev names; Fs_Type itself
   --    when neither says -- then no Windows-family rule is assumed: the
   --    volume may be any FUSE block filesystem, and refusing a name it
   --    stores would leave no way to make it, where a write it refuses still
   --    fails with its own error.
   function Fuse_Block_Type (Fs_Type : String; Udev_Record : String) return String;

end Hostkit.Filesystem_Rules;
