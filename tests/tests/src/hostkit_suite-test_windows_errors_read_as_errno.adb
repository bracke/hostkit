separate (Hostkit_Suite)
procedure Test_Windows_Errors_Read_As_Errno
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package WE renames Hostkit.Windows_Errors;
   package HE renames Hostkit.Errors;

   function Errno_Of (Code : Natural) return Integer is (WE.Errno_Of (Interfaces.Unsigned_32 (Code)));

   Folder  : constant String := Ada.Directories.Compose (Scratch, "hostkit-errno-dir");
   Missing : constant String :=
     Ada.Directories.Compose (Ada.Directories.Compose (Scratch, "hostkit-errno-none"), "child");
begin
   --  The table is pure, so it is checked on every host: the numbers are the
   --  Windows runtime's own wherever this runs.
   Assert (Errno_Of (0) = 0, "ERROR_SUCCESS is no error");
   Assert (Errno_Of (5) = 13, "ERROR_ACCESS_DENIED is EACCES");
   Assert (Errno_Of (32) = 16, "ERROR_SHARING_VIOLATION is EBUSY: someone else holds the file");
   Assert (Errno_Of (33) = 16, "ERROR_LOCK_VIOLATION is EBUSY");
   Assert (Errno_Of (112) = 28, "ERROR_DISK_FULL is ENOSPC");
   Assert (Errno_Of (39) = 28, "ERROR_HANDLE_DISK_FULL is ENOSPC");
   Assert (Errno_Of (1295) = 28, "ERROR_DISK_QUOTA_EXCEEDED is ENOSPC, Windows having no EDQUOT");
   Assert (Errno_Of (19) = 30, "ERROR_WRITE_PROTECT is EROFS");
   Assert (Errno_Of (206) = 38, "ERROR_FILENAME_EXCED_RANGE is ENAMETOOLONG");
   Assert (Errno_Of (80) = 17 and then Errno_Of (183) = 17, "ERROR_FILE_EXISTS and ERROR_ALREADY_EXISTS are EEXIST");
   Assert (Errno_Of (2) = 2 and then Errno_Of (3) = 2, "a missing file or folder is ENOENT");
   Assert (Errno_Of (53) = 110 and then Errno_Of (67) = 110,
           "an unreachable network path or share is EHOSTUNREACH, not ENOENT: a sleeping server answers so too");
   Assert (Errno_Of (1921) = 114, "ERROR_CANT_RESOLVE_FILENAME, a looping link, is ELOOP, not ENOENT");
   Assert (Errno_Of (145) = 41, "ERROR_DIR_NOT_EMPTY is ENOTEMPTY");
   Assert (Errno_Of (17) = 18, "ERROR_NOT_SAME_DEVICE is EXDEV");
   Assert (Errno_Of (1314) = 1, "ERROR_PRIVILEGE_NOT_HELD is EPERM");
   Assert (Errno_Of (681) = 114, "ERROR_STOPPED_ON_SYMLINK is ELOOP, the UCRT's 114");
   Assert (Errno_Of (123) = 22, "ERROR_INVALID_NAME is EINVAL");
   Assert (Errno_Of (99_999) = 22, "an unknown code is EINVAL, as _dosmaperr reads one");

   --  On Windows the causes a caller tells apart are the ones the table
   --  gives, so a refusal read through it lands on the right message.
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (HE.Code_Of (HE.Permission_Denied) = Errno_Of (5), "a denied access reads as Permission_Denied");
      Assert (HE.Code_Of (HE.Busy) = Errno_Of (32), "a sharing violation reads as Busy");
      Assert (HE.Code_Of (HE.No_Space) = Errno_Of (112), "a full disk reads as No_Space");
      Assert (HE.Code_Of (HE.Read_Only_Filesystem) = Errno_Of (19), "write protection reads as read-only");
      Assert (HE.Code_Of (HE.Name_Too_Long) = Errno_Of (206), "a name too long reads as Name_Too_Long");
   end if;

   --  A refused create says why through errno on every host -- on Windows
   --  only because Hostkit puts GetLastError there. EEXIST and ENOENT are
   --  17 and 2 on all three.
   if Ada.Directories.Exists (Folder) then
      Ada.Directories.Delete_Tree (Folder);
   end if;
   Assert (Hostkit.Fs.Create_Directory (Folder), "a fresh folder is made");
   GNAT.OS_Lib.Set_Errno (0);
   Assert (not Hostkit.Fs.Create_Directory (Folder), "an existing folder is refused");
   Assert (GNAT.OS_Lib.Errno = 17, "and errno says it exists:" & Integer'Image (GNAT.OS_Lib.Errno));
   GNAT.OS_Lib.Set_Errno (0);
   Assert (not Hostkit.Fs.Create_Directory (Missing), "a folder in a missing one is refused");
   Assert (GNAT.OS_Lib.Errno = 2, "and errno says the way is missing:" & Integer'Image (GNAT.OS_Lib.Errno));
   Ada.Directories.Delete_Tree (Folder);

   --  A refused replace: a read-only target is cleared once and tried again
   --  at once, a file held a moment is waited for, anything else ends it.
   declare
      use type WE.Replace_Step;
      function Step (Code : Natural; Read_Only, Cleared : Boolean; Attempt : Positive) return WE.Replace_Step is
        (WE.After_Refused_Replace (Interfaces.Unsigned_32 (Code), Read_Only, Cleared, Attempt, Attempts => 10));
   begin
      Assert (Step (5, True, False, 1) = WE.Clear_Read_Only, "a read-only target is cleared");
      Assert (Step (5, True, False, 10) = WE.Clear_Read_Only, "even on the last attempt");
      Assert (Step (5, True, True, 2) = WE.Try_Again, "cleared once only, then waited for");
      Assert (Step (5, False, False, 1) = WE.Try_Again, "a denial with no read-only target is waited for");
      Assert (Step (32, False, False, 3) = WE.Try_Again, "a sharing violation is waited for");
      Assert (Step (33, True, False, 3) = WE.Try_Again, "a lock violation is waited for, read-only or not");
      Assert (Step (32, False, False, 10) = WE.Give_Up, "not past the last attempt");
      Assert (Step (2, True, False, 1) = WE.Give_Up, "a missing source ends it at once");
   end;
end Test_Windows_Errors_Read_As_Errno;
