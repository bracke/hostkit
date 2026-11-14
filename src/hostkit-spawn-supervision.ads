--  Supervising a helper process: ending it now and asking whether it has ended.
--
--  A program that runs workers of its own -- a file manager's copy helper, a
--  build's compile jobs -- needs exactly two things beyond Start and Wait: a
--  way to end a worker that will not stop by itself, and a yes/no on whether a
--  worker is gone. Both have a host-shaped answer, which is why they live here
--  and not in every program that supervises.
package Hostkit.Spawn.Supervision is

   --  End a process now.
   --
   --  POSIX sends SIGKILL. Where the host has no such signal, or refuses it,
   --  this falls back to Hostkit.Process.Request_Stop, which on Windows
   --  terminates the process.
   --
   --  @param Item Process to end.
   --  @return True when the request reached the process.
   function Stop_Now (Item : Process_Handle) return Boolean;

   --  Whether a process has ended, without waiting for it.
   --
   --  Ended means there is nothing left to wait for: it exited, was killed by
   --  a signal, was lost to the host (collected elsewhere), or the handle is
   --  one the host will not answer for (then Result.State is Wait_Lost). A
   --  stopped or continued process has not ended. On POSIX an ended child is
   --  reaped by this call, so it is asked once; release the handle afterwards.
   --
   --  @param Item Process to ask about.
   --  @param Result What the host answered, meaningful when this returns True.
   --  @return True when the process has ended.
   function Has_Ended (Item : Process_Handle; Result : out Status) return Boolean;

   --  @param Item Process to ask about.
   --  @return True when the process has ended.
   function Has_Ended (Item : Process_Handle) return Boolean;

end Hostkit.Spawn.Supervision;
