with Ada.Environment_Variables;

separate (Hostkit_Shell_Cases)
procedure Test_A_Replaced_Environment_Reaches_The_Child
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   --  Run env_reader under exactly Given, asking it for HOSTKIT_TEST, and check
   --  that it exited Expected_Code having said something that starts Expected.
   procedure Check
     (Given         : Hostkit.String_Vectors.Vector;
      Expected      : String;
      Expected_Code : Integer;
      Label         : String);

   procedure Check
     (Given         : Hostkit.String_Vectors.Vector;
      Expected      : String;
      Expected_Code : Integer;
      Label         : String)
   is
      Ends    : D.Pipe_Ends := (Read_End => D.Invalid, Write_End => D.Invalid);
      Options : Hostkit.Spawn.Options;
      Child   : Hostkit.Spawn.Process_Handle;
      Result  : Hostkit.Spawn.Status;
      Args    : Hostkit.String_Vectors.Vector;
   begin
      Assert (D.Create_Pipe (Ends), Label & ": could not create a pipe");
      Assert (D.Set_Inheritable (Ends.Write_End, True),
              Label & ": could not make the write end inheritable");

      Args.Append (Ada.Strings.Unbounded.To_Unbounded_String ("HOSTKIT_TEST"));

      Options.Output := Ends.Write_End;
      Options.Replace_Environment := True;
      Options.Environment := Given;

      Assert (Hostkit.Spawn.Start (Companion ("env_reader"), Args, Options,
                                   Child)
              = Hostkit.Spawn.Spawn_Ok,
              Label & ": spawning with a replaced environment failed");

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
                 Label & ": the child was still running five seconds after it "
                 & "was spawned with a replaced environment");
         Hostkit.Spawn.Release (Child);

         Assert (Result.State = Hostkit.Spawn.Wait_Exited
                   and then Result.Exit_Code = Expected_Code,
                 Label & ": the child did not exit with"
                 & Integer'Image (Expected_Code) & ": "
                 & Hostkit.Spawn.Wait_State'Image (Result.State)
                 & Integer'Image (Result.Exit_Code));

         --  Only now, and only because the child is gone: whatever it wrote is
         --  in the pipe and no read can block.
         declare
            Output : constant String := Drain (Ends.Read_End);
         begin
            Assert (Output'Length >= Expected'Length
                      and then Output (Output'First .. Output'First + Expected'Length - 1)
                               = Expected,
                    Label & ": the child did not say " & Expected & ": ["
                    & Output & "]");
         end;
      end;

      D.Close (Ends.Read_End);
   exception
      when others =>
         --  Whatever failed, leave no pipe open and no child running behind it:
         --  the next test would otherwise inherit both.
         D.Close (Ends.Write_End);
         D.Close (Ends.Read_End);

         if Hostkit.Spawn.Is_Valid (Child) then
            declare
               Stopped : constant Boolean :=
                 Hostkit.Process.Request_Stop (Hostkit.Spawn.Process_Id (Child));
               Waited  : constant Boolean :=
                 Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result);
               pragma Unreferenced (Stopped, Waited);
            begin
               Hostkit.Spawn.Release (Child);
            end;
         end if;

         raise;
   end Check;

   Given : Hostkit.String_Vectors.Vector;
begin
   --  What it read, not merely that it ran: a child that started with no
   --  environment at all would exit 4 and say "absent", which is the failure
   --  this first case exists to catch.
   Given.Append (Ada.Strings.Unbounded.To_Unbounded_String ("HOSTKIT_TEST=given"));
   Check (Given, "value:given", 0, "one variable");

   --  And an empty replacement is an empty environment, not "no replacement":
   --  the child must not see the variable this process has. Windows once took
   --  an empty block to mean "inherit mine".
   Ada.Environment_Variables.Set ("HOSTKIT_TEST", "inherited");
   Given.Clear;

   begin
      Check (Given, "absent", 4, "no variables");
   exception
      when others =>
         Ada.Environment_Variables.Clear ("HOSTKIT_TEST");
         raise;
   end;

   Ada.Environment_Variables.Clear ("HOSTKIT_TEST");
end Test_A_Replaced_Environment_Reaches_The_Child;
