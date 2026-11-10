--  The host's numbers for the reasons a file-system call fails.
--
--  A caller that wants to say why a call failed -- the disk is full, the
--  name is too long -- reads errno, but the numbers are the host's own:
--  ENAMETOOLONG is 36 on Linux, 63 on macOS and 38 on Windows, and GNAT's
--  System.OS_Constants lacks most of them. Each host's body holds its
--  errno.h values.
package Hostkit.Errors is

   --  The reasons told apart.
   type Cause is
     (No_Space,
      Quota_Exceeded,
      Permission_Denied,
      Not_Permitted,
      Read_Only_Filesystem,
      Busy,
      Text_Busy,
      Name_Too_Long);

   --  The errno value this host uses for a cause.
   --
   --  @param Item Cause to look up.
   --  @return The host's errno for Item, or zero when the host has none
   --    (EDQUOT on Windows) or no table.
   function Code_Of (Item : Cause) return Integer;

end Hostkit.Errors;
