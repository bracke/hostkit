with Interfaces.C;

--  The few numbers and symbol names where macOS differs from Linux under the
--  bodies the two share (src/platform/posix). Linux has its own package of
--  this name; only one of the two is ever in a build.
private package Hostkit.Posix_Abi is

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

end Hostkit.Posix_Abi;
