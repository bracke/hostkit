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

   --  The filesystem type of the deepest mount point that contains Target_Path,
   --  read out of the contents of a Linux /proc/self/mountinfo file. Empty when
   --  no mount line covers the path (which cannot normally happen, since "/"
   --  always does) or the text cannot be parsed.
   function Filesystem_Type_For_Mount
     (Mountinfo   : String;
      Target_Path : String)
      return String;

end Hostkit.Filesystem_Rules;
