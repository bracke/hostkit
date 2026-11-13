with Interfaces.C;

--  What the Linux and macOS bodies share below the level of a public unit:
--  the calling thread's errno, and the children started detached that are
--  still to be collected. Every body that reads or sets errno used to
--  bind the per-thread location itself, each copy naming the host's symbol;
--  it is bound once here, and the one name that differs between the hosts
--  comes from Hostkit.Posix_Abi. This package is in the POSIX source
--  directory only, so no other host ever sees it.
private package Hostkit.Posix is

   --  The calling thread's errno.
   --
   --  @return The value errno holds now.
   function Errno return Interfaces.C.int;

   --  Set the calling thread's errno.
   --
   --  @param Code The value to give it; 0 clears it.
   procedure Set_Errno (Code : Interfaces.C.int);

   --  Remember a child started detached -- by Hostkit.Process.Launch or by
   --  Open_Native -- so that Reap_Noted_Children collects it once it has
   --  finished. Only a child noted here is ever collected by that: a child
   --  that Hostkit.Spawn or Run_Captured started is theirs to wait for, and a
   --  waitpid on any child would take its status from under them.
   --
   --  @param Process_Id The child's process id.
   procedure Note_Child (Process_Id : Integer);

   --  Collect each noted child that has already finished, and forget it.
   --  Never waits for one still running; that one stays noted for next time.
   procedure Reap_Noted_Children;

end Hostkit.Posix;
