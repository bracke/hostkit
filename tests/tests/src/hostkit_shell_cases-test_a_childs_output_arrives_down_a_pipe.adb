separate (Hostkit_Shell_Cases)
procedure Test_A_Childs_Output_Arrives_Down_A_Pipe
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Ends     : D.Pipe_Ends;
   Options  : Hostkit.Spawn.Options;
   Child    : Hostkit.Spawn.Process_Handle;
   Result   : Hostkit.Spawn.Status;
   Outcome  : Hostkit.Spawn.Spawn_Outcome;
   No_Args  : Hostkit.String_Vectors.Vector;
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");

   --  Only the write end goes to the child, and only it is made inheritable.
   Assert (D.Set_Inheritable (Ends.Write_End, True),
           "could not make the write end inheritable");

   Options.Output := Ends.Write_End;
   Outcome := Hostkit.Spawn.Start (Companion ("sleeper"), No_Args, Options, Child);

   Assert (Outcome = Hostkit.Spawn.Spawn_Ok,
           "spawning the sleeper failed: "
           & Hostkit.Spawn.Spawn_Outcome'Image (Outcome));

   --  The parent's own copy has to go, or the read below never ends: the
   --  pipe stays open as long as any copy of the write end does, and the
   --  parent is holding one.
   D.Close (Ends.Write_End);

   declare
      Output : constant String := Drain (Ends.Read_End);
   begin
      Assert (Contains (Output, "out-line"),
              "the child's standard output did not arrive down the pipe; got: "
              & Output);
   end;

   D.Close (Ends.Read_End);

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the child failed");
   Assert (Result.State = Hostkit.Spawn.Wait_Exited,
           "the child did not exit normally: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));
end Test_A_Childs_Output_Arrives_Down_A_Pipe;
