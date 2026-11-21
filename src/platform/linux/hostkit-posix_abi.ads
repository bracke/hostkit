with Interfaces.C;
with System;

--  The few numbers and symbol names where Linux differs from macOS under the
--  bodies the two share (src/platform/posix). macOS has its own package of
--  this name; only one of the two is ever in a build.
private package Hostkit.Posix_Abi is

   use type Interfaces.C.int;

   --  errno is a macro over a per-thread location, and this is the function
   --  it expands to on glibc. Reading a global named "errno" would link on
   --  some hosts and read the wrong thread's value on all of them.
   Errno_Location : constant String := "__errno_location";

   --  Signal numbers, from asm/signal.h. These are the x86/ARM values, which
   --  is every Linux GNAT targets; the alpha/mips variants differ and are not
   --  supported here.
   SIGHUP   : constant Interfaces.C.int := 1;
   SIGINT   : constant Interfaces.C.int := 2;
   SIGQUIT  : constant Interfaces.C.int := 3;
   SIGKILL  : constant Interfaces.C.int := 9;
   SIGPIPE  : constant Interfaces.C.int := 13;
   SIGTERM  : constant Interfaces.C.int := 15;
   SIGCHLD  : constant Interfaces.C.int := 17;
   SIGCONT  : constant Interfaces.C.int := 18;
   SIGSTOP  : constant Interfaces.C.int := 19;
   SIGTSTP  : constant Interfaces.C.int := 20;
   SIGTTIN  : constant Interfaces.C.int := 21;
   SIGTTOU  : constant Interfaces.C.int := 22;
   SIGWINCH : constant Interfaces.C.int := 28;

   --  struct passwd, whole: getpwnam_r and getpwuid_r write the record into
   --  one the caller owns, so every field has to be there, not only the
   --  ones read. glibc's layout; macOS has more fields.
   type Passwd_Record is record
      Name     : System.Address := System.Null_Address;
      Password : System.Address := System.Null_Address;
      User_Id  : Interfaces.C.unsigned := 0;
      Group_Id : Interfaces.C.unsigned := 0;
      Gecos    : System.Address := System.Null_Address;
      Home     : System.Address := System.Null_Address;
      Shell    : System.Address := System.Null_Address;
   end record
     with Convention => C;

   --  sysconf names for the buffer the reentrant account lookups suggest.
   SC_Getgr_R_Size_Max : constant Interfaces.C.int := 69;
   SC_Getpw_R_Size_Max : constant Interfaces.C.int := 70;

   --  errno values the spawn body tells apart that are not the same on both
   --  hosts. The rest (ENOENT, EACCES, ...) agree and stay in that body.
   E_Loop        : constant := 40;
   E_Nametoolong : constant := 36;

   --  waitpid's WCONTINUED: 8 here, 0x10 on macOS.
   WCONTINUED : constant Interfaces.C.int := 8;

   --  Whether a wait status (WIFCONTINUED) says a stopped child was resumed.
   --  glibc gives it as the whole status word 0xFFFF.
   --
   --  @param Raw The status waitpid stored.
   --  @return True for a resumed child.
   function Is_Continued (Raw : Interfaces.C.int) return Boolean is (Raw = 16#FFFF#);

   --  sigprocmask's SIG_SETMASK: 2 here, 3 on macOS.
   SIG_SETMASK : constant Interfaces.C.int := 2;

   --  TIOCSCTTY: "make this terminal my controlling terminal". A small number
   --  here, where BSD encodes the direction and size of the argument into it.
   TIOCSCTTY : constant Interfaces.C.unsigned_long := 16#0000_540E#;

   --  open(2) flags the pseudo-terminal body passes. O_NOCTTY is 0o400 on
   --  every Linux GNAT targets here (x86, ARM); macOS has 0x20000.
   O_Rdwr   : constant Interfaces.C.int := 8#2#;
   O_Noctty : constant Interfaces.C.int := 8#400#;

   --  Whether a write to the controller of a pseudo-terminal whose device side
   --  nothing holds fails. It does not here: the bytes go into the line
   --  discipline's buffer, where they stay, and only a read then reports the
   --  end.
   Pty_Write_Fails_When_Unheld : constant Boolean := False;

   --  The address of the environment pointer (char ***) the next exec passes
   --  on. Writing through it replaces that environment and -- because execvp
   --  reads PATH from it -- the PATH the lookup uses. Here that is
   --  "extern char **environ" itself.
   --
   --  @return The address of environ.
   function Environment_Slot return System.Address;

private

   Environ : System.Address
     with Import => True, Convention => C, External_Name => "environ";

   function Environment_Slot return System.Address is (Environ'Address);

end Hostkit.Posix_Abi;
