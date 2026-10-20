--  Apple silicon macOS never had the 32-bit-inode structs, so the plain names
--  already use the 64-bit-inode layout and libSystem exports no $INODE64
--  variants: binding those failed at the link.
private package Hostkit.Darwin_Symbols is
   Stat    : constant String := "stat";
   Lstat   : constant String := "lstat";
   Fstat   : constant String := "fstat";
   Fstatat : constant String := "fstatat";
   Statfs  : constant String := "statfs";
   Readdir : constant String := "readdir";

end Hostkit.Darwin_Symbols;
