with Interfaces.C;
with System;

--  The few numbers and symbol names where macOS differs from Linux under the
--  bodies the two share (src/platform/posix). Linux has its own package of
--  this name; only one of the two is ever in a build.
private package Hostkit.Posix_Abi is

   use type Interfaces.C.int;

   --  errno is a macro over a per-thread location, and this is the function
   --  it expands to on macOS, where glibc's __errno_location does not exist.
   --  Reading a global named "errno" would read the wrong thread's value.
   Errno_Location : constant String := "__error";

   --  Signal numbers, from sys/signal.h. The first sixteen agree with Linux;
   --  from there the two diverge, and this is where a shared table would go
   --  wrong. SIGSTOP is 17 here and 19 on Linux, SIGCHLD 20 here and 17
   --  there -- so a Linux table used on macOS would stop a job when it meant
   --  to be told a child had exited.
   SIGHUP   : constant Interfaces.C.int := 1;
   SIGINT   : constant Interfaces.C.int := 2;
   SIGQUIT  : constant Interfaces.C.int := 3;
   SIGKILL  : constant Interfaces.C.int := 9;
   SIGPIPE  : constant Interfaces.C.int := 13;
   SIGTERM  : constant Interfaces.C.int := 15;
   SIGSTOP  : constant Interfaces.C.int := 17;
   SIGTSTP  : constant Interfaces.C.int := 18;
   SIGCONT  : constant Interfaces.C.int := 19;
   SIGCHLD  : constant Interfaces.C.int := 20;
   SIGTTIN  : constant Interfaces.C.int := 21;
   SIGTTOU  : constant Interfaces.C.int := 22;
   SIGWINCH : constant Interfaces.C.int := 28;

   --  struct passwd, whole: getpwnam_r and getpwuid_r write the record into
   --  one the caller owns, so every field has to be there, not only the
   --  ones read. BSD keeps a change time and a login class between the group
   --  id and the gecos field, and an expiry after the shell; glibc's shorter
   --  record would be overrun here and read the wrong pointer for the home.
   type Passwd_Record is record
      Name     : System.Address := System.Null_Address;
      Password : System.Address := System.Null_Address;
      User_Id  : Interfaces.C.unsigned := 0;
      Group_Id : Interfaces.C.unsigned := 0;
      Change   : Interfaces.C.long := 0;
      Class    : System.Address := System.Null_Address;
      Gecos    : System.Address := System.Null_Address;
      Home     : System.Address := System.Null_Address;
      Shell    : System.Address := System.Null_Address;
      Expire   : Interfaces.C.long := 0;
   end record
     with Convention => C;

   pragma Compile_Time_Error
     (Passwd_Record'Size /= 72 * 8, "Darwin struct passwd must be 72 bytes");

   --  sysconf names for the buffer the reentrant account lookups suggest.
   SC_Getgr_R_Size_Max : constant Interfaces.C.int := 70;
   SC_Getpw_R_Size_Max : constant Interfaces.C.int := 71;

   --  errno values the spawn body tells apart that are not the same on both
   --  hosts: ELOOP and ENAMETOOLONG are 62 and 63 here, 40 and 36 on Linux.
   E_Loop        : constant := 62;
   E_Nametoolong : constant := 63;

   --  waitpid's WCONTINUED: 0x10 here, 8 on Linux.
   WCONTINUED : constant Interfaces.C.int := 16#10#;

   --  Whether a wait status (WIFCONTINUED) says a stopped child was resumed.
   --  BSD encodes it as a stop whose "signal" is 0x13, where Linux uses the
   --  whole status word 0xFFFF. Testing for the Linux form here would report
   --  every resumed job as stopped, and a shell would show a running job as
   --  suspended for ever.
   --
   --  @param Raw The status waitpid stored.
   --  @return True for a resumed child.
   function Is_Continued (Raw : Interfaces.C.int) return Boolean is
     (Raw mod 256 = 16#7F# and then (Raw / 256) mod 256 = 16#13#);

   --  sigprocmask's SIG_SETMASK: 3 here, 2 on Linux.
   SIG_SETMASK : constant Interfaces.C.int := 3;

   --  TIOCSCTTY: "make this terminal my controlling terminal". BSD encodes an
   --  ioctl request from its direction, the size of the argument and a
   --  two-character group, so this is not the small number Linux uses
   --  (0x540E). 0x20007461 is "no argument, group t, number 97".
   TIOCSCTTY : constant Interfaces.C.unsigned_long := 16#2000_7461#;

   --  open(2) flags the pseudo-terminal body passes. O_NOCTTY is 0x20000 here
   --  and 0o400 on Linux; opening the device side with the Linux number would
   --  set O_SHLOCK instead and leave the terminal free to become this
   --  process's controlling one -- so a shell would start taking the Ctrl-C
   --  meant for the child it just made it for.
   O_Rdwr   : constant Interfaces.C.int := 16#0002#;
   O_Noctty : constant Interfaces.C.int := 16#2_0000#;

   --  Whether a write to the controller of a pseudo-terminal whose device side
   --  nothing holds fails. It does here: once the last descriptor for the
   --  device side is closed, the write fails with EIO rather than being
   --  buffered, and a caller sees a transfer that took no bytes.
   Pty_Write_Fails_When_Unheld : constant Boolean := True;

   --  The address of the environment pointer (char ***) the next exec passes
   --  on. Writing through it replaces that environment and -- because execvp
   --  reads PATH from it -- the PATH the lookup uses.
   --
   --  Not "extern char **environ" as on Linux. On macOS that symbol is not
   --  reliably reachable from anything but the main executable, and Apple
   --  documents _NSGetEnviron as the way to get at it; it returns the address
   --  of the pointer.
   --
   --  @return The address of the environment pointer.
   function Environment_Slot return System.Address
     with Import => True, Convention => C, External_Name => "_NSGetEnviron";

end Hostkit.Posix_Abi;
