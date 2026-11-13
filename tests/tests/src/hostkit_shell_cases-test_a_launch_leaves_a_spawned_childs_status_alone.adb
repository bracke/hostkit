separate (Hostkit_Shell_Cases)
procedure Test_A_Launch_Leaves_A_Spawned_Childs_Status_Alone
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   No_Args : Hostkit.String_Vectors.Vector;
begin
   Assert (Hostkit.Spawn.Start (Companion ("noop"), No_Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the noop companion did not start it");

   --  The spawned child finishes and waits, uncollected, for its status to be
   --  asked for. Meanwhile two launches start and finish children of their own,
   --  and each wakes the reaper: the second wakes it after the first launched
   --  child is gone too, so the reaper has something of its own to collect
   --  while the spawned child's status is there for the taking.
   delay 0.5;
   Assert (Hostkit.Process.Launch (Companion ("noop"), No_Args), "the first launch did not start");
   delay 0.5;
   Assert (Hostkit.Process.Launch (Companion ("noop"), No_Args), "the second launch did not start");
   delay 0.5;

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the spawned child failed");
   Hostkit.Spawn.Release (Child);
   Assert (Result.State = Hostkit.Spawn.Wait_Exited,
           "the spawned child's status was taken by a launch's reaper: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));
   Assert (Result.Exit_Code = 0,
           "the spawned child's exit status was lost; got"
           & Integer'Image (Result.Exit_Code));
end Test_A_Launch_Leaves_A_Spawned_Childs_Status_Alone;
