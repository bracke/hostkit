separate (Hostkit_Shell_Cases)
procedure Test_A_Child_Runs_On_A_Terminal
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   --  CR LF, because the two hosts disagree about which one Enter is and
   --  each accepts the pair.
   --
   --  Bounds written out. A positional aggregate for an unconstrained array
   --  starts at the index type's first value, which for a stream element
   --  offset is a large negative number, and every length computed from it
   --  afterwards overflows.
   Typed : constant Ada.Streams.Stream_Element_Array (1 .. 7) :=
     [Character'Pos ('h'), Character'Pos ('e'), Character'Pos ('l'),
      Character'Pos ('l'), Character'Pos ('o'), 13, 10];

   --  Everything read from a terminal so far, as text.
   function Gathered
     (Terminal : Hostkit.Pty.Pair;
      Rounds   : Positive;
      Wanted   : String;
      Into     : in out Unbounded_String) return Boolean;

   function Gathered
     (Terminal : Hostkit.Pty.Pair;
      Rounds   : Positive;
      Wanted   : String;
      Into     : in out Unbounded_String) return Boolean is
   begin
      for Attempt in 1 .. Rounds loop
         --  Waiting before reading, rather than reading and hoping. A read
         --  of an empty pipe waits for ever on the host with no
         --  non-blocking mode, and a test that hangs is a job that reports
         --  nothing.
         if D.Wait_Readable (Terminal.From_Child, 50) then
            declare
               Buffer : Ada.Streams.Stream_Element_Array (1 .. 1024);
               Taken  : Ada.Streams.Stream_Element_Offset;
            begin
               if D.Read (Terminal.From_Child, Buffer, Taken) = D.Transfer_Ok
                 and then Taken >= Buffer'First
               then
                  for Index in Buffer'First .. Taken loop
                     Append (Into, Character'Val (Natural (Buffer (Index))));
                  end loop;
               end if;
            end;
         end if;

         --  An empty pattern is how a caller says "just read what is
         --  there": Index raises on one, and drain-until-nothing has no
         --  text to wait for.
         if Wanted'Length > 0
           and then Ada.Strings.Fixed.Index (To_String (Into), Wanted) > 0
         then
            return True;
         end if;
      end loop;

      return False;
   end Gathered;

   Writing : Hostkit.Pty.Pair;
   Reading : Hostkit.Pty.Pair;

   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;

   Hang    : Hostkit.String_Vectors.Vector;
   Nothing : Hostkit.String_Vectors.Vector;

   Last : Ada.Streams.Stream_Element_Offset;
   Seen : Unbounded_String;

   Stopped : Boolean;
   pragma Unreferenced (Stopped);
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   Hang.Append (Ada.Strings.Unbounded.To_Unbounded_String ("--hang"));

   --  Nought: what the child sees of the streams it was given. Written to a
   --  file rather than to those streams, because a child asked whether its
   --  output is a terminal cannot answer on that output if the answer is
   --  that it has none.
   declare
      Told : Hostkit.String_Vectors.Vector;
      Said : Unbounded_String;

      Room : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Containing_Directory
             (Ada.Command_Line.Command_Name),
           "terminal-report.txt");
   begin
      if Ada.Directories.Exists (Room) then
         Ada.Directories.Delete_File (Room);
      end if;

      Told.Append (Ada.Strings.Unbounded.To_Unbounded_String (Room));

      Assert (Hostkit.Pty.Open (Writing), "could not open a terminal");
      Assert (Hostkit.Pty.Attach (Writing, Options),
              "could not arrange to start a reporter on the terminal");
      Assert (Hostkit.Spawn.Start
                (Companion ("terminal_reporter"), Told, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the reporter would not start on a terminal");

      Hostkit.Pty.Close_Device (Writing);

      for Attempt in 1 .. 200 loop
         exit when Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
                   and then Result.State /= Hostkit.Spawn.Wait_Running;
         delay 0.05;
      end loop;

      declare
         Ignored : constant Boolean := Gathered (Writing, 20, "", Seen);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;

      Hostkit.Pty.Close (Writing);

      if Ada.Directories.Exists (Room) then
         declare
            Report : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Open (Report, Ada.Text_IO.In_File, Room);

            while not Ada.Text_IO.End_Of_File (Report) loop
               Append (Said, Ada.Text_IO.Get_Line (Report) & " ");
            end loop;

            Ada.Text_IO.Close (Report);
         end;
      end if;

      --  A child on a terminal has one on both its streams. This is the
      --  claim every other terminal test rests on, and it is the one that
      --  says which half is wrong when a child on a console writes into the
      --  void.
      Assert (Ada.Strings.Fixed.Index (To_String (Said), "input=TRUE") > 0
              and then
              Ada.Strings.Fixed.Index (To_String (Said), "output=TRUE") > 0
              and then
              Ada.Strings.Fixed.Index (To_String (Said), "wrote=TRUE") > 0,
              "a child started on a terminal did not see one. It reported ["
              & To_String (Said) & "] and the terminal gave back ["
              & To_String (Seen) & "]");
   end;

   Seen := Null_Unbounded_String;
   Options := (others => <>);

   --  One: the child's output reaches the parent's side.
   Assert (Hostkit.Pty.Open (Writing), "could not open a terminal");
   Assert (Hostkit.Pty.Set_Size (Writing, (Rows => 24, Columns => 80)),
           "could not size the terminal");
   Assert (Hostkit.Pty.Attach (Writing, Options),
           "could not arrange to start a child on the terminal");

   Assert (Hostkit.Spawn.Start
             (Companion ("sleeper"), Hang, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the sleeper would not start on a terminal");

   Hostkit.Pty.Close_Device (Writing);

   declare
      Arrived : constant Boolean :=
        Gathered (Writing, 200, "out-line", Seen);
   begin
      --  Terminated before asserting, so that a failure does not leave a
      --  child of this suite running for the rest of the job. Whether it
      --  worked is not this test's claim: the assert below is.
      Stopped := Hostkit.Process.Request_Stop
                   (Hostkit.Spawn.Process_Id (Child));

      Assert (Arrived,
              "a child on a terminal wrote a line the parent never saw: ["
              & To_String (Seen) & "]");
   end;

   Hostkit.Pty.Close (Writing);

   --  Two: what is typed at the child reaches it.
   Seen := Null_Unbounded_String;
   Options := (others => <>);

   Assert (Hostkit.Pty.Open (Reading), "could not open a second terminal");
   Assert (Hostkit.Pty.Set_Size (Reading, (Rows => 24, Columns => 80)),
           "could not size the second terminal");
   Assert (Hostkit.Pty.Attach (Reading, Options),
           "could not arrange to start a reader on the terminal");

   Assert (Hostkit.Spawn.Start
             (Companion ("echoer"), Nothing, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the echoer would not start on a terminal");

   Hostkit.Pty.Close_Device (Reading);

   --  A moment for the host to attach a client to the terminal, and for
   --  whatever it says when it does. A console host announces itself the
   --  moment it has one; a pseudo-terminal says nothing at all, so this
   --  finds something on one host and nothing on the other, and neither is
   --  a failure. What it is for is not typing at a terminal whose far side
   --  is not there yet.
   declare
      Ignored : constant Boolean := Gathered (Reading, 10, "read:hello", Seen);
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   Assert (D.Write (Reading.To_Child, Typed, Last) = D.Transfer_Ok,
           "could not type into the terminal");

   declare
      Answered : constant Boolean :=
        Gathered (Reading, 200, "read:hello", Seen);

      Ended : Boolean := False;
   begin
      for Attempt in 1 .. 100 loop
         if Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
           and then Result.State /= Hostkit.Spawn.Wait_Running
         then
            Ended := True;
            exit;
         end if;

         delay 0.05;
      end loop;

      --  How the child ended is part of the failure. A child that exited 3
      --  read nothing at all, which is a different fault from one that read
      --  the wrong thing or wrote where this cannot see it -- and a failure
      --  that cannot tell those apart costs a run to find out.
      Assert (Answered,
              "the child never read what was typed at its terminal. It "
              & (if Ended
                 then "ended "
                      & Hostkit.Spawn.Wait_State'Image (Result.State)
                      & " with status"
                      & Integer'Image (Result.Exit_Code)
                 else "was still running")
              & ", and the terminal gave back ["
              & To_String (Seen) & "]");

      Assert (Ended, "the child never finished after reading its line");
   end;

   --  Drained before closing. A console host with output nobody has taken
   --  can keep the close waiting, and the same drain costs nothing on a
   --  host where the child's side is already gone.
   declare
      Ignored : constant Boolean := Gathered (Reading, 20, "", Seen);
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   Hostkit.Pty.Close (Reading);
end Test_A_Child_Runs_On_A_Terminal;
