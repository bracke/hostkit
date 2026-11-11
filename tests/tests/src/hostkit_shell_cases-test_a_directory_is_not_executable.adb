separate (Hostkit_Shell_Cases)
procedure Test_A_Directory_Is_Not_Executable
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   --  Set by a call whose success is what is asserted, not its result.
   pragma Warnings (Off, Child);
   No_Args : Hostkit.String_Vectors.Vector;
   Outcome : Hostkit.Spawn.Spawn_Outcome;
begin
   Outcome := Hostkit.Spawn.Start
     (Ada.Directories.Current_Directory, No_Args, Options, Child);

   --  Distinguished from "not found", because a user who typed a directory
   --  name needs to be told which mistake they made.
   Assert (Outcome = Hostkit.Spawn.Spawn_Not_Executable
           or else Outcome = Hostkit.Spawn.Spawn_Denied,
           "a directory was not reported as unexecutable; got "
           & Hostkit.Spawn.Spawn_Outcome'Image (Outcome));
end Test_A_Directory_Is_Not_Executable;
