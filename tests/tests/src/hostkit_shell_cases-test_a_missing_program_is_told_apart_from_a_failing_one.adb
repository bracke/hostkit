separate (Hostkit_Shell_Cases)
procedure Test_A_Missing_Program_Is_Told_Apart_From_A_Failing_One
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   No_Args : Hostkit.String_Vectors.Vector;
   Outcome : Hostkit.Spawn.Spawn_Outcome;
begin
   --  The whole point of the report pipe. Without it this is exit status
   --  127, which a real program is entitled to return, and a shell could
   --  not honestly say "command not found".
   Outcome := Hostkit.Spawn.Start
     (Companion ("no-such-program-anywhere"), No_Args, Options, Child);

   Assert (Outcome = Hostkit.Spawn.Spawn_Not_Found,
           "a missing program was not reported as missing; got "
           & Hostkit.Spawn.Spawn_Outcome'Image (Outcome));
   Assert (not Hostkit.Spawn.Is_Valid (Child),
           "a failed spawn handed back a valid handle");
end Test_A_Missing_Program_Is_Told_Apart_From_A_Failing_One;
