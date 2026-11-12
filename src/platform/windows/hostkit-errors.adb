with Interfaces;

with Hostkit.Win32;
with Hostkit.Windows_Errors;

package body Hostkit.Errors is

   --  errno.h of the UCRT and of mingw-w64; Windows has no EDQUOT.
   function Code_Of (Item : Cause) return Integer is
     (case Item is
         when No_Space             => 28,
         when Quota_Exceeded       => 0,
         when Permission_Denied    => 13,
         when Not_Permitted        => 1,
         when Read_Only_Filesystem => 30,
         when Busy                 => 16,
         when Text_Busy            => 139,
         when Name_Too_Long        => 38);

   --  Into the C runtime's own errno, which GNAT.OS_Lib.Errno reads back.
   procedure Set_Errno_From_Last_Error is
   begin
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Hostkit.Win32.Get_Last_Error));
   end Set_Errno_From_Last_Error;

end Hostkit.Errors;
