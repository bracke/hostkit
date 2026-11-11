separate (Hostkit_Shell_Cases)
procedure Test_A_Group_Can_Be_Signalled_As_One
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   Args    : Hostkit.String_Vectors.Vector;
begin
   if not Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Terminate) then
      Skip ("Test_A_Group_Can_Be_Signalled_As_One", "this host has no signals, so no process groups");
      return;
   end if;

   Args.Append (To_Unbounded_String ("--hang"));
   Options.Group := Hostkit.Spawn.Group_New;

   Assert (Hostkit.Spawn.Start (Companion ("sleeper"), Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the hanging sleeper failed");

   --  Sent to the group, not the process: that is what makes one Ctrl-C
   --  reach every stage of a pipeline rather than only the first.
   Assert (Hostkit.Signals.Send_To_Group
             (Hostkit.Spawn.Group_Id (Child), Hostkit.Signals.Signal_Terminate),
           "signalling the child's group failed");

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the signalled child failed");
   Assert (Result.State = Hostkit.Spawn.Wait_Signalled,
           "a child killed by a signal was not reported as signalled: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));
   Assert (Result.Signal_Known
           and then Result.Terminating_Signal = Hostkit.Signals.Signal_Terminate,
           "the terminating signal was not identified");
end Test_A_Group_Can_Be_Signalled_As_One;
