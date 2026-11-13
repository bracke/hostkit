with Interfaces.C;

--  The few numbers and symbol names where Linux differs from macOS under the
--  bodies the two share (src/platform/posix). macOS has its own package of
--  this name; only one of the two is ever in a build.
private package Hostkit.Posix_Abi is

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

end Hostkit.Posix_Abi;
