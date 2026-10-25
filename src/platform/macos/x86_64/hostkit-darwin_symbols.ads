--  Intel macOS: since the 64-bit inode transition the unsuffixed names
--  describe the older, narrower structs; the $INODE64 entry points fill the
--  64-bit-inode layout the Ada records bind.
--  Public so that every body binding one of these calls on macOS -- the
--  regular-file and directory-write-access bodies fstat a descriptor, and a
--  consumer may too -- takes the name for this architecture from here rather
--  than hard-coding the Intel one.
package Hostkit.Darwin_Symbols is
   Stat    : constant String := "stat$INODE64";
   Lstat   : constant String := "lstat$INODE64";
   Fstat   : constant String := "fstat$INODE64";
   Fstatat : constant String := "fstatat$INODE64";
   Statfs  : constant String := "statfs$INODE64";
   Readdir : constant String := "readdir$INODE64";
   --  <dirent.h> aliases the directory-stream openers along with readdir; a
   --  stream must come from the matching opener.
   Opendir   : constant String := "opendir$INODE64";
   Fdopendir : constant String := "fdopendir$INODE64";

end Hostkit.Darwin_Symbols;
