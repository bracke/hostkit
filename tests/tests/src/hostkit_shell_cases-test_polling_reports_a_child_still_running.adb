separate (Hostkit_Shell_Cases)
procedure Test_Polling_Reports_A_Child_Still_Running
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   --  Set by a call whose success is what is asserted, not its result.
   pragma Warnings (Off, Result);
   Args    : Hostkit.String_Vectors.Vector;
begin
   Args.Append (To_Unbounded_String ("--hang"));

   Assert (Hostkit.Spawn.Start (Companion ("sleeper"), Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the hanging sleeper failed");

   --  A poll must return, and must say running. A shell refreshing its job
   --  table before a prompt cannot afford this call to block.
   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result),
           "polling a running child failed");
   Assert (Result.State = Hostkit.Spawn.Wait_Running,
           "a running child was not reported as running: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));

   --  Ended by whatever this host has. A signal where there are signals,
   --  and Request_Stop where there are none -- which is what that call is
   --  for: "Windows has no signal to send: it opens the process and
   --  terminates it, which is the only way to say it there."
   --
   --  Without this the test killed nothing on Windows and then blocked for
   --  ever reaping a child that hangs by design. It took the whole job's
   --  budget with it, twice, and reported nothing either time.
   if Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Kill) then
      Assert (Hostkit.Signals.Send_To_Process
                (Hostkit.Spawn.Process_Id (Child), Hostkit.Signals.Signal_Kill),
              "could not kill the hanging sleeper");
   else
      Assert (Hostkit.Process.Request_Stop (Hostkit.Spawn.Process_Id (Child)),
              "could not stop the hanging sleeper on a host without signals");
   end if;

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "reaping the killed sleeper failed");
end Test_Polling_Reports_A_Child_Still_Running;
