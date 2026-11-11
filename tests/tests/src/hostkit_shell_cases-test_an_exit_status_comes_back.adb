separate (Hostkit_Shell_Cases)
procedure Test_An_Exit_Status_Comes_Back
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   No_Args : Hostkit.String_Vectors.Vector;
begin
   Assert (Hostkit.Spawn.Start (Companion ("failing"), No_Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the failing companion did not start it");

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the failing companion failed");
   Assert (Result.State = Hostkit.Spawn.Wait_Exited,
           "the failing companion did not exit normally");
   Assert (Result.Exit_Code = 7,
           "the failing companion's exit status was lost; got"
           & Integer'Image (Result.Exit_Code));
end Test_An_Exit_Status_Comes_Back;
