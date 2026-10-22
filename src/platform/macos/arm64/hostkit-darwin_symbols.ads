--  Apple silicon macOS never had the 32-bit-inode structs, so the plain names
--  already use the 64-bit-inode layout and libSystem exports no $INODE64
--  variants: binding those failed at the link.
--  Public so that a consumer binding one of these calls on macOS -- files'
--  regular-file and rename checks fstat a descriptor -- takes the name for
--  this architecture from here rather than hard-coding the Intel one.
package Hostkit.Darwin_Symbols is
   Stat    : constant String := "stat";
   Lstat   : constant String := "lstat";
   Fstat   : constant String := "fstat";
   Fstatat : constant String := "fstatat";
   Statfs  : constant String := "statfs";
   Readdir : constant String := "readdir";
   --  <dirent.h> aliases the directory-stream openers along with readdir; a
   --  stream must come from the matching opener.
   Opendir   : constant String := "opendir";
   Fdopendir : constant String := "fdopendir";

end Hostkit.Darwin_Symbols;
