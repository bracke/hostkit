separate (Hostkit_Shell_Cases)
procedure Test_A_Supervised_Child_Ends_When_Told
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   Ended   : Boolean := False;
   Args    : Hostkit.String_Vectors.Vector;
begin
   Args.Append (To_Unbounded_String ("--hang"));
   Assert (Hostkit.Spawn.Start (Companion ("sleeper"), Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the hanging sleeper failed");

   --  A worker that is still running has not ended, and asking does not wait.
   Assert (not Hostkit.Spawn.Supervision.Has_Ended (Child),
           "a running child was reported as ended");

   Assert (Hostkit.Spawn.Supervision.Stop_Now (Child),
           "Stop_Now did not reach the hanging sleeper");

   --  Ending is asynchronous: poll, bounded, until the host says it is over.
   for Attempt in 1 .. 200 loop
      Ended := Hostkit.Spawn.Supervision.Has_Ended (Child, Result);
      exit when Ended;
      delay 0.05;
   end loop;
   Assert (Ended, "a child told to stop never ended");
   Assert (Result.State in Hostkit.Spawn.Wait_Signalled | Hostkit.Spawn.Wait_Exited,
           "a stopped child ended as " & Hostkit.Spawn.Wait_State'Image (Result.State));
   Hostkit.Spawn.Release (Child);

   --  A handle the host will not answer for leaves nothing to wait for.
   Assert (Hostkit.Spawn.Supervision.Has_Ended (Hostkit.Spawn.Invalid_Process, Result)
           and then Result.State = Hostkit.Spawn.Wait_Lost,
           "an invalid handle was not reported as ended and lost");
end Test_A_Supervised_Child_Ends_When_Told;
