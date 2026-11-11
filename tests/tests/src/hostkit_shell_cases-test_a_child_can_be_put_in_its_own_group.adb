separate (Hostkit_Shell_Cases)
procedure Test_A_Child_Can_Be_Put_In_Its_Own_Group
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   --  Set by a call whose success is what is asserted, not its result.
   pragma Warnings (Off, Result);
   No_Args : Hostkit.String_Vectors.Vector;
begin
   if not Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Terminate) then
      --  A host without signals has no process groups either. Skipped
      --  rather than asserted away: the refusal is the correct answer there.
      Skip ("Test_A_Child_Can_Be_Put_In_Its_Own_Group", "this host has no signals, so no process groups");
      return;
   end if;

   Options.Group := Hostkit.Spawn.Group_New;
   Assert (Hostkit.Spawn.Start (Companion ("sleeper"), No_Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning into a new group failed");

   --  A new group is led by the child, so the group id is the process id.
   --  This is what Send_To_Group and the terminal handover are given.
   Assert (Hostkit.Spawn.Group_Id (Child) = Hostkit.Spawn.Process_Id (Child),
           "a child in a new group did not lead it:"
           & Integer'Image (Hostkit.Spawn.Group_Id (Child))
           & " vs" & Integer'Image (Hostkit.Spawn.Process_Id (Child)));

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the grouped child failed");
end Test_A_Child_Can_Be_Put_In_Its_Own_Group;
