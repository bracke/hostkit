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

   --  What a replace (MoveFileExW with MOVEFILE_REPLACE_EXISTING) does next
   --  once the host refused it with a code.
   type Replace_Step is
     (Clear_Read_Only,
      --  The target has the read-only attribute, which refuses a replace
      --  (ERROR_ACCESS_DENIED) where POSIX rename does not look at the
      --  target's mode: clear it and try again at once.
      Try_Again,
      --  Someone holds a file a moment (a virus scanner, the indexer) and
      --  did not share deletion: wait a little and try again.
      Give_Up);

   --  The step after a refused replace.
   --
   --  @param Code What GetLastError said for the refused move.
   --  @param Target_Read_Only Whether the target has the read-only attribute
   --    (asked only after ERROR_ACCESS_DENIED).
   --  @param Read_Only_Cleared Whether this replace already cleared it.
   --  @param Attempt The attempt just refused, from 1.
   --  @param Attempts How many attempts the replace makes in all.
   --  @return Clear_Read_Only once, for a read-only target that refused;
   --    Try_Again for a refusal that may pass while attempts remain;
   --    Give_Up otherwise.
   function After_Refused_Replace
     (Code              : Interfaces.Unsigned_32;
      Target_Read_Only  : Boolean;
      Read_Only_Cleared : Boolean;
      Attempt           : Positive;
      Attempts          : Positive)
      return Replace_Step;

   --  How often an operation on a file someone holds a moment (a virus
   --  scanner, the search indexer, not sharing it) is tried in all: Windows
   --  Defender has been seen to hold a just-written file for over a second.
   Held_Attempts : constant := 20;

   --  The pause after attempt Attempt was refused for a hold: growing by
   --  20 ms an attempt, at most a quarter second, so Held_Attempts tries
   --  wait about 3.6 s in all before giving up.
   --
   --  @param Attempt The attempt just refused, from 1.
   --  @return The pause before the next attempt.
   function Held_Delay (Attempt : Positive) return Duration is
     (Duration'Min (Duration (Attempt) * 0.02, 0.25));

end Hostkit.Windows_Errors;
