with Interfaces;

--  Reading a Windows system error code as the errno a caller asks about.
--
--  Hostkit's Windows bodies call Win32 directly -- CreateDirectoryW,
--  MoveFileExW, DeleteFileW and the rest -- and Win32 says why a call failed
--  through GetLastError, never errno. A caller that tells a full disk from a
--  refusal by reading errno (as files does, through GNAT.OS_Lib.Errno) then
--  saw nothing and fell back to its generic message. Hostkit.Errors'
--  Set_Errno_From_Last_Error puts the reason into errno; this is the table it
--  reads, which is pure text and so lives in the shared source, tested on
--  every platform.
package Hostkit.Windows_Errors is

   --  The errno the Windows C runtime (UCRT and mingw-w64 alike) uses for a
   --  Windows system error code. The numbers are the Windows runtime's own,
   --  on every host this is compiled for: Hostkit.Errors.Code_Of on Windows
   --  agrees with them, not Linux's or macOS's.
   --
   --  A sharing or lock violation is EBUSY (someone else holds the file), a
   --  refusal by the ACL is EACCES, a write-protected medium is EROFS, a
   --  missing privilege is EPERM, a link refused rather than followed
   --  (ERROR_STOPPED_ON_SYMLINK) is ELOOP, as O_NOFOLLOW's refusal is on
   --  POSIX. A code without a closer meaning is EINVAL, as the runtime's
   --  own _dosmaperr reads one.
   --
   --  @param Code A value GetLastError returned.
   --  @return The errno for Code; zero for ERROR_SUCCESS.
   function Errno_Of (Code : Interfaces.Unsigned_32) return Integer;

   --  Set errno to Errno_Of (Code), for a Windows call that hands its
   --  reason back as its result (SetSecurityInfo, GetNamedSecurityInfoW)
   --  rather than through GetLastError; Hostkit.Errors'
   --  Set_Errno_From_Last_Error is this of GetLastError. Nothing changes
   --  when Code is zero.
   --
   --  @param Code A Windows system error code.
   procedure Set_Errno_From (Code : Interfaces.Unsigned_32);

end Hostkit.Windows_Errors;
