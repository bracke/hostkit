separate (Hostkit_Shell_Cases)
procedure Test_An_Exit_Code_Comes_Back_Readable
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Asked   : Hostkit.String_Vectors.Vector;
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;

   use type Hostkit.Host.Kind;

   Wanted : constant Integer :=
     (if Hostkit.Host.Current = Hostkit.Host.Windows then -1 else 255);
begin
   Asked.Append (Ada.Strings.Unbounded.To_Unbounded_String ("-1"));

   Assert (Hostkit.Spawn.Start (Companion ("leaver"), Asked, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the leaver would not start");

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "the leaver was not waited for");

   Assert (Result.State = Hostkit.Spawn.Wait_Exited,
           "a program that ended with a status did not exit: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));

   Assert (Result.Exit_Code = Wanted,
           "an exit code came back as" & Integer'Image (Result.Exit_Code)
           & " rather than" & Integer'Image (Wanted));
end Test_An_Exit_Code_Comes_Back_Readable;
