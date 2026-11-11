separate (Hostkit_Shell_Cases)
procedure Test_A_Replaced_Environment_Reaches_The_Child
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Ends    : D.Pipe_Ends;
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   Args    : Hostkit.String_Vectors.Vector;
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");
   Assert (D.Set_Inheritable (Ends.Write_End, True),
           "could not make the write end inheritable");

   Args.Append (Ada.Strings.Unbounded.To_Unbounded_String ("HOSTKIT_TEST"));

   Options.Output := Ends.Write_End;
   Options.Replace_Environment := True;
   Options.Environment.Append
     (Ada.Strings.Unbounded.To_Unbounded_String ("HOSTKIT_TEST=given"));

   Assert (Hostkit.Spawn.Start (Companion ("env_reader"), Args, Options,
                                Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning with a replaced environment failed");

   D.Close (Ends.Write_End);

   --  Waited for before anything is read, and not for ever. A test that
   --  drains a pipe until end of file cannot fail on a host where the child
   --  never runs: it blocks, the job reaches its limit, and what comes back
   --  is a cancelled run that says nothing. This one gives the child a few
   --  seconds and then reports what it found -- which is the difference
   --  between an answer and thirty minutes of silence.
   declare
      Settled : Boolean := False;
   begin
      for Attempt in 1 .. 100 loop
         if Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
           and then Result.State /= Hostkit.Spawn.Wait_Running
         then
            Settled := True;
            exit;
         end if;

         delay 0.05;
      end loop;

      Assert (Settled,
              "the child was still running five seconds after it was "
              & "spawned with a replaced environment");

      Assert (Result.State = Hostkit.Spawn.Wait_Exited
                and then Result.Exit_Code = 0,
              "the child did not exit cleanly: "
              & Hostkit.Spawn.Wait_State'Image (Result.State)
              & Integer'Image (Result.Exit_Code));

      --  Only now, and only because the child is gone: whatever it wrote is
      --  in the pipe and no read can block.
      declare
         Output : constant String := Drain (Ends.Read_End);
      begin
         --  What it read, not merely that it ran: a child that started with
         --  no environment at all would exit 4 and say "absent", which is
         --  the failure this exists to catch.
         Assert (Output'Length > 5
                   and then Output (Output'First .. Output'First + 5)
                            = "value:",
                 "the child did not see the variable it was given: ["
                 & Output & "]");
      end;
   end;

   D.Close (Ends.Read_End);
end Test_A_Replaced_Environment_Reaches_The_Child;
