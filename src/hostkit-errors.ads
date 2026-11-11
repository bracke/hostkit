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

   --  Put into errno why the host call that just failed failed, where the
   --  host says so somewhere else. Windows' own API reports through
   --  GetLastError and leaves errno alone, so a caller that reads errno to
   --  tell a full disk from a refusal saw nothing; a Windows body calls this
   --  straight after each failing call whose failure its caller reports,
   --  before any other call can overwrite the last error. It reads the code
   --  through Hostkit.Windows_Errors.Errno_Of, and leaves errno as it was
   --  when the last error is zero. A POSIX call sets errno itself, so on
   --  every other host this does nothing.
   procedure Set_Errno_From_Last_Error;

end Hostkit.Errors;
