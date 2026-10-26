with Ada.Containers.Vectors;

--  The mounted filesystems, as the host lists them.
--
--  Linux keeps the table in /proc/mounts: one line per mount -- source, mount
--  point, type, options -- with a space or a backslash in a field written as an
--  octal escape (\040). Windows has drive letters instead, and macOS volumes
--  under /Volumes; neither keeps such a table, so there the list is empty and a
--  caller finds volumes by their own folders. An empty table is "this host does
--  not say", never "nothing is mounted".
package Hostkit.Mounts is

   --  One mounted filesystem.
   type Mount is record
      --  What is mounted: a block device (/dev/sdb1), a share
      --  (//server/share), or a name for a pseudo filesystem (proc, tmpfs).
      Source          : UString;
      --  Where, with its escapes decoded.
      Mount_Point     : UString;
      --  The filesystem type (ext4, vfat, cifs, fuse.sshfs, ...).
      Filesystem_Type : UString;
      --  The mount options, comma-separated, as listed.
      Options         : UString;
   end record;

   package Mount_Vectors is new Ada.Containers.Vectors (Positive, Mount);

   --  The mounts in the order the host lists them; empty where it keeps no
   --  table (Windows, macOS) or the table cannot be read.
   --
   --  @return The mounts.
   function Table return Mount_Vectors.Vector;

   --  The mount at exactly Mount_Point in Mounts.
   --
   --  @param Mounts A table, from Table.
   --  @param Mount_Point Absolute path of a mount point.
   --  @param Found Set to whether there is one.
   --  @return It, when Found.
   function Find (Mounts : Mount_Vectors.Vector; Mount_Point : String; Found : out Boolean) return Mount;

   --  Whether the block device Source (/dev/sdb1, /dev/nvme0n1p2) sits on a
   --  removable disk, as Linux's /sys/block/<disk>/removable says. Known is
   --  False where the host does not say (another host, a share, a device
   --  sysfs does not list): then the answer is False, which is not "fixed".
   --
   --  @param Source A mount's source.
   --  @param Known Set to whether the host answered.
   --  @return True when the disk is removable.
   function Removable (Source : String; Known : out Boolean) return Boolean;

end Hostkit.Mounts;
