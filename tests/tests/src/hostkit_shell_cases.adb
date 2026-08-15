with Ada.Text_IO;

with AUnit.Assertions;

with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Interfaces;

with Hostkit;
with Hostkit.Descriptors;
with Hostkit.Locks;
with Hostkit.Pty;
with Hostkit.Host;
with Hostkit.Process;
with Hostkit.Signals;
with Hostkit.Spawn;
with Hostkit.Terminal_Control;
with Hostkit.Terminal_Control.Differences;

package body Hostkit_Shell_Cases is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element_Array;
   use type Hostkit.Descriptors.Descriptor;
   use type Hostkit.Descriptors.Transfer_Outcome;
   use type Hostkit.Signals.Disposition;
   use type Hostkit.Signals.Signal;
   use type Hostkit.Spawn.Spawn_Outcome;
   use type Hostkit.Spawn.Wait_State;
   use type Hostkit.Locks.Lock_Outcome;
   use type Hostkit.Terminal_Control.Mode;
   use type Ada.Directories.File_Size;

   package D renames Hostkit.Descriptors;

   --  Whether this host's terminal has a side this process can ask questions
   --  of. A pseudo-terminal's device side is a descriptor here in the parent,
   --  so its modes, its size and its cursor can all be read and written from
   --  this side. A pseudo-console's child side belongs to the console host:
   --  there is no descriptor here to save a mode from, and the questions below
   --  are not questions on that host rather than questions with a wrong
   --  answer.
   function Has_A_Device_Side (Item : Hostkit.Pty.Pair) return Boolean
   is (D.Is_Valid (Item.Device));

   --  The suite's own directory: the companion programs are built beside it.
   function Companion (Name : String) return String is
      Self : constant String := Ada.Command_Line.Command_Name;
      Dir  : constant String := Ada.Directories.Containing_Directory (Self);
   begin
      if Ada.Directories.Exists (Ada.Directories.Compose (Dir, Name & ".exe")) then
         return Ada.Directories.Compose (Dir, Name & ".exe");
      end if;

      return Ada.Directories.Compose (Dir, Name);
   exception
      when others =>
         return Name;
   end Companion;

   --  Read a descriptor to end-of-file. Used to prove a child's output actually
   --  arrived, which is the only thing that proves the wiring worked.
   function Drain (Item : D.Descriptor) return String is
      Result : Unbounded_String;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 256);
      Last   : Ada.Streams.Stream_Element_Offset;
      Status : D.Transfer_Outcome;
   begin
      loop
         Status := D.Read (Item, Buffer, Last);

         exit when Status = D.Transfer_End_Of_File;

         if Status = D.Transfer_Ok then
            for Index in Buffer'First .. Last loop
               Append (Result, Character'Val (Natural (Buffer (Index))));
            end loop;
         elsif Status /= D.Transfer_Interrupted then
            exit;
         end if;
      end loop;

      return To_String (Result);
   end Drain;

   function Contains (Haystack, Needle : String) return Boolean is
   begin
      if Needle'Length = 0 or else Needle'Length > Haystack'Length then
         return Needle'Length = 0;
      end if;

      for Start in Haystack'First .. Haystack'Last - Needle'Length + 1 loop
         if Haystack (Start .. Start + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;

      return False;
   end Contains;

   -----------------------------------------------------------------------
   --  Descriptors
   -----------------------------------------------------------------------

   procedure Test_A_Pipe_Carries_Bytes_And_Then_Ends
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ends   : D.Pipe_Ends;
      Sent   : constant Ada.Streams.Stream_Element_Array (1 .. 5) :=
        [72, 101, 108, 108, 111];
      Last   : Ada.Streams.Stream_Element_Offset;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 16);
   begin
      Assert (D.Create_Pipe (Ends), "could not create a pipe");
      Assert (D.Is_Valid (Ends.Read_End) and then D.Is_Valid (Ends.Write_End),
              "a created pipe handed back an invalid end");

      Assert (D.Write (Ends.Write_End, Sent, Last) = D.Transfer_Ok,
              "writing to a fresh pipe failed");
      Assert (Last = Sent'Last, "a five byte write into an empty pipe was short");

      Assert (D.Read (Ends.Read_End, Buffer, Last) = D.Transfer_Ok,
              "reading back from the pipe failed");
      Assert (Last = 5 and then Buffer (1 .. 5) = Sent,
              "the pipe did not return the bytes that went in");

      --  The property a pipeline depends on: end-of-file arrives when the last
      --  write end closes, and not before.
      D.Close (Ends.Write_End);
      Assert (D.Read (Ends.Read_End, Buffer, Last) = D.Transfer_End_Of_File,
              "closing the write end did not produce end-of-file");

      D.Close (Ends.Read_End);
   end Test_A_Pipe_Carries_Bytes_And_Then_Ends;

   procedure Test_Closing_Twice_Is_Harmless
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ends : D.Pipe_Ends;
   begin
      Assert (D.Create_Pipe (Ends), "could not create a pipe");

      D.Close (Ends.Read_End);
      Assert (not D.Is_Valid (Ends.Read_End), "Close left the descriptor valid");

      --  The second close must not reach the host at all. If it did, and the
      --  number had been reused by then, it would close something else -- the
      --  bug this design removes rather than documents.
      D.Close (Ends.Read_End);
      Assert (not D.Is_Valid (Ends.Read_End), "closing twice revived the descriptor");

      D.Close (Ends.Write_End);
   end Test_Closing_Twice_Is_Harmless;

   procedure Test_A_File_Round_Trips_Through_A_Descriptor
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory,
                                 "hostkit-descriptor-roundtrip.tmp");
      Item   : D.Descriptor;
      --  Set by a call this test requires to refuse, so it is never read.
      pragma Warnings (Off, Item);
      Sent   : constant Ada.Streams.Stream_Element_Array (1 .. 3) := [97, 98, 99];
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 8);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Assert (D.Open_File (Path, D.Open_Write_Truncate, Item),
              "could not open a file for writing");
      Assert (D.Write (Item, Sent, Last) = D.Transfer_Ok, "writing to the file failed");
      D.Close (Item);

      Assert (D.Open_File (Path, D.Open_Read, Item), "could not reopen the file");
      Assert (D.Read (Item, Buffer, Last) = D.Transfer_Ok, "reading the file failed");
      Assert (Last = 3 and then Buffer (1 .. 3) = Sent,
              "the file did not return the bytes that went in");
      D.Close (Item);

      --  Opening a file that is not there is a refusal, not a creation.
      Assert (not D.Open_File (Path & ".absent", D.Open_Read, Item),
              "opening an absent file for reading reported success");

      Ada.Directories.Delete_File (Path);
   end Test_A_File_Round_Trips_Through_A_Descriptor;

   -----------------------------------------------------------------------
   --  Spawning
   -----------------------------------------------------------------------

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

   procedure Test_A_Child_Reads_The_Input_It_Was_Given
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      To_Child   : D.Pipe_Ends;
      From_Child : D.Pipe_Ends;
      Options    : Hostkit.Spawn.Options;
      Child      : Hostkit.Spawn.Process_Handle;
      Result     : Hostkit.Spawn.Status;
      --  Set by a call whose success is what is asserted, not its result.
      pragma Warnings (Off, Result);
      No_Args    : Hostkit.String_Vectors.Vector;
      Line       : constant Ada.Streams.Stream_Element_Array (1 .. 7) :=
        [104, 101, 108, 108, 111, 10, 10];
      Last       : Ada.Streams.Stream_Element_Offset;
      --  Set by a call whose success is what is asserted, not its result.
      pragma Warnings (Off, Last);
   begin
      Assert (D.Create_Pipe (To_Child), "could not create the input pipe");
      Assert (D.Create_Pipe (From_Child), "could not create the output pipe");

      Assert (D.Set_Inheritable (To_Child.Read_End, True), "input end not inheritable");
      Assert (D.Set_Inheritable (From_Child.Write_End, True), "output end not inheritable");

      Options.Input  := To_Child.Read_End;
      Options.Output := From_Child.Write_End;

      Assert (Hostkit.Spawn.Start (Companion ("echoer"), No_Args, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "spawning the echoer failed");

      D.Close (To_Child.Read_End);
      D.Close (From_Child.Write_End);

      Assert (D.Write (To_Child.Write_End, Line, Last) = D.Transfer_Ok,
              "writing to the child failed");
      D.Close (To_Child.Write_End);

      declare
         Output : constant String := Drain (From_Child.Read_End);
      begin
         --  Two pipes at once, in both directions. This is the shape of every
         --  pipeline stage, and the test that would catch the ends being
         --  crossed.
         Assert (Contains (Output, "read:hello"),
                 "the child did not read what it was given; got: " & Output);
      end;

      D.Close (From_Child.Read_End);

      Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
              "waiting for the echoer failed");
   end Test_A_Child_Reads_The_Input_It_Was_Given;

   procedure Test_Polling_Reports_A_Child_Still_Running
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Options : Hostkit.Spawn.Options;
      Child   : Hostkit.Spawn.Process_Handle;
      Result  : Hostkit.Spawn.Status;
      --  Set by a call whose success is what is asserted, not its result.
      pragma Warnings (Off, Result);
      Args    : Hostkit.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("--hang"));

      Assert (Hostkit.Spawn.Start (Companion ("sleeper"), Args, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "spawning the hanging sleeper failed");

      --  A poll must return, and must say running. A shell refreshing its job
      --  table before a prompt cannot afford this call to block.
      Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result),
              "polling a running child failed");
      Assert (Result.State = Hostkit.Spawn.Wait_Running,
              "a running child was not reported as running: "
              & Hostkit.Spawn.Wait_State'Image (Result.State));

      --  Ended by whatever this host has. A signal where there are signals,
      --  and Request_Stop where there are none -- which is what that call is
      --  for: "Windows has no signal to send: it opens the process and
      --  terminates it, which is the only way to say it there."
      --
      --  Without this the test killed nothing on Windows and then blocked for
      --  ever reaping a child that hangs by design. It took the whole job's
      --  budget with it, twice, and reported nothing either time.
      if Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Kill) then
         Assert (Hostkit.Signals.Send_To_Process
                   (Hostkit.Spawn.Process_Id (Child), Hostkit.Signals.Signal_Kill),
                 "could not kill the hanging sleeper");
      else
         Assert (Hostkit.Process.Request_Stop (Hostkit.Spawn.Process_Id (Child)),
                 "could not stop the hanging sleeper on a host without signals");
      end if;

      Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
              "reaping the killed sleeper failed");
   end Test_Polling_Reports_A_Child_Still_Running;

   -----------------------------------------------------------------------
   --  Signals
   -----------------------------------------------------------------------

   procedure Test_Signal_Names_And_Numbers_Agree
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Decoded : Hostkit.Signals.Signal;
   begin
      for Item in Hostkit.Signals.Signal loop
         Assert (Hostkit.Signals.Name (Item)'Length > 0,
                 "a signal has no name: " & Hostkit.Signals.Signal'Image (Item));

         if Hostkit.Signals.Is_Supported (Item) then
            Assert (Hostkit.Signals.Number (Item) > 0,
                    "a supported signal has no number: "
                    & Hostkit.Signals.Name (Item));

            --  Round trip. A wait status carries a number, and reporting the
            --  wrong signal for it is worse than reporting none.
            Assert (Hostkit.Signals.From_Number
                      (Hostkit.Signals.Number (Item), Decoded),
                    "a supported signal's number did not decode: "
                    & Hostkit.Signals.Name (Item));
            Assert (Decoded = Item,
                    "a signal number decoded to the wrong signal: "
                    & Hostkit.Signals.Name (Item) & " became "
                    & Hostkit.Signals.Name (Decoded));
         else
            Assert (Hostkit.Signals.Number (Item) = -1,
                    "an unsupported signal reported a number: "
                    & Hostkit.Signals.Name (Item));
         end if;
      end loop;
   end Test_Signal_Names_And_Numbers_Agree;

   procedure Test_An_Unknown_Signal_Number_Is_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Decoded : Hostkit.Signals.Signal;
      --  Set by a call this test requires to refuse, so it is never read.
      pragma Warnings (Off, Decoded);
   begin
      --  A signal this enumeration does not name must come back as unknown,
      --  not as whichever literal happens to be first. A job that died of
      --  SIGSEGV must not be reported as terminated by SIGTERM.
      Assert (not Hostkit.Signals.From_Number (12_345, Decoded),
              "a nonsense signal number was accepted");
   end Test_An_Unknown_Signal_Number_Is_Refused;

   procedure Test_A_Disposition_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Current : Hostkit.Signals.Disposition;
   begin
      if not Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Pipe) then
         return;
      end if;

      --  SIGPIPE, because it is the one a shell must ignore or die on its
      --  first truncated pipeline.
      Assert (Hostkit.Signals.Set_Disposition
                (Hostkit.Signals.Signal_Pipe, Hostkit.Signals.Disposition_Ignore),
              "could not ignore SIGPIPE");
      Assert (Hostkit.Signals.Current_Disposition
                (Hostkit.Signals.Signal_Pipe, Current),
              "could not read back the SIGPIPE disposition");
      Assert (Current = Hostkit.Signals.Disposition_Ignore,
              "SIGPIPE did not stay ignored");

      Assert (Hostkit.Signals.Set_Disposition
                (Hostkit.Signals.Signal_Pipe, Hostkit.Signals.Disposition_Default),
              "could not restore SIGPIPE");
      Assert (Hostkit.Signals.Current_Disposition
                (Hostkit.Signals.Signal_Pipe, Current),
              "could not read back the restored SIGPIPE disposition");
      Assert (Current = Hostkit.Signals.Disposition_Default,
              "SIGPIPE did not go back to the default");
   end Test_A_Disposition_Round_Trips;

   procedure Test_Kill_And_Stop_Cannot_Be_Caught
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  POSIX forbids it, and this must refuse rather than appear to succeed:
      --  a shell that believed it had ignored SIGKILL would be relying on
      --  something that cannot happen.
      Assert (not Hostkit.Signals.Set_Disposition
                (Hostkit.Signals.Signal_Kill, Hostkit.Signals.Disposition_Ignore),
              "ignoring SIGKILL reported success");
      Assert (not Hostkit.Signals.Set_Disposition
                (Hostkit.Signals.Signal_Stop, Hostkit.Signals.Disposition_Ignore),
              "ignoring SIGSTOP reported success");
   end Test_Kill_And_Stop_Cannot_Be_Caught;

   procedure Test_Signalling_Nothing_Is_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  kill(2) reads a non-positive pid as "a group" or "everything I may
      --  signal". A caller that passed a bad id meant one process, and
      --  signalling every process it owns instead is not a near miss -- for a
      --  shell it would be every job it started, and itself.
      Assert (not Hostkit.Signals.Send_To_Process (0, Hostkit.Signals.Signal_Terminate),
              "signalling process 0 was allowed");
      Assert (not Hostkit.Signals.Send_To_Process (-1, Hostkit.Signals.Signal_Terminate),
              "signalling process -1 was allowed");
      Assert (not Hostkit.Signals.Send_To_Group (0, Hostkit.Signals.Signal_Terminate),
              "signalling group 0 was allowed");
   end Test_Signalling_Nothing_Is_Refused;

   -----------------------------------------------------------------------
   --  Terminal control and pseudo-terminals
   -----------------------------------------------------------------------

   procedure Test_A_Pipe_Has_No_Terminal_Answers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ends  : D.Pipe_Ends;
      Size  : Hostkit.Terminal_Control.Window_Size;
      --  Set by a call this test requires to refuse, so it is never read.
      pragma Warnings (Off, Size);
      Group : Integer;
      Saved : Hostkit.Terminal_Control.Mode;
      --  Set by a call this test requires to refuse, so it is never read.
      pragma Warnings (Off, Saved);
   begin
      Assert (D.Create_Pipe (Ends), "could not create a pipe");

      --  Every one of these must refuse rather than answer. A pipe has no size,
      --  and zero rows is not "how big is it" -- a caller that stored it would
      --  lay out for a terminal with no room, or divide by it.
      Assert (not D.Is_Terminal (Ends.Read_End), "a pipe claimed to be a terminal");
      Assert (not Hostkit.Terminal_Control.Size (Ends.Read_End, Size),
              "a pipe reported a window size");
      Assert (not Hostkit.Terminal_Control.Save_Mode (Ends.Read_End, Saved),
              "a pipe let its terminal settings be saved");
      Assert (not Hostkit.Terminal_Control.Set_Raw (Ends.Read_End),
              "a pipe was put into raw mode");

      if Hostkit.Terminal_Control.Supports_Foreground_Group then
         Assert (not Hostkit.Terminal_Control.Foreground_Group (Ends.Read_End, Group),
                 "a pipe reported a foreground process group");
      end if;

      D.Close (Ends.Read_End);
      D.Close (Ends.Write_End);
   end Test_A_Pipe_Has_No_Terminal_Answers;

   procedure Test_A_Pseudo_Terminal_Is_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item : Hostkit.Pty.Pair;
   begin
      if not Hostkit.Pty.Is_Supported then
         --  A host with neither pseudo-terminals nor a console of its own. The
         --  refusal is the correct answer, and a consumer degrades on the
         --  question rather than on a failed Open.
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");
      Assert (D.Is_Valid (Item.To_Child) and then D.Is_Valid (Item.From_Child),
              "a pseudo-terminal handed back an invalid side for the parent");

      if D.Is_Valid (Item.Device) then
         --  A host with pseudo-terminals. The whole point of the thing: unlike
         --  a pipe, both sides are terminals, so a program that checks behaves
         --  as it does for a user.
         Assert (D.Is_Terminal (Item.Device),
                 "the device side of a pseudo-terminal is not a terminal");
         Assert (D.Is_Terminal (Item.From_Child),
                 "the controlling side of a pseudo-terminal is not a terminal");

         Assert (Hostkit.Pty.Device_Name (Item)'Length > 0,
                 "a pseudo-terminal could not name its device side");
      else
         --  A host whose answer is a console: two ordinary pipes for the
         --  parent and a console for the child. The pipes are pipes and do not
         --  pretend otherwise -- what makes the child see a terminal is the
         --  console, not these -- and there is no device to name.
         Assert (Hostkit.Spawn.Is_Attached (Item.Console),
                 "a host with no device side handed back no console either");
         Assert (Hostkit.Pty.Device_Name (Item)'Length = 0,
                 "a pseudo-console named a device it has not got");
      end if;

      Hostkit.Pty.Close (Item);
      Assert (not D.Is_Valid (Item.To_Child), "Close left a parent side valid");
      Assert (not D.Is_Valid (Item.From_Child), "Close left a parent side valid");
      Assert (not D.Is_Valid (Item.Device), "Close left the device valid");
   end Test_A_Pseudo_Terminal_Is_A_Terminal;

   --  A child in a session of its own controls the terminal it was given, and
   --  a Ctrl-C typed at that terminal reaches it.
   --
   --  This is the whole reason Options.Controlling_Terminal exists. Without
   --  it, a program handed a pseudo-terminal as its streams does not control
   --  it -- the terminal belongs to whoever opened it -- so the line
   --  discipline has no foreground group of that terminal's session to signal,
   --  and typing Ctrl-C does nothing at all. What proves the difference is the
   --  child dying of an interrupt it could not otherwise have received.
   procedure Test_A_Child_Can_Own_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Terminal : Hostkit.Pty.Pair;
      Options  : Hostkit.Spawn.Options;
      Child    : Hostkit.Spawn.Process_Handle;
      Result   : Hostkit.Spawn.Status;
      Ended    : Boolean := False;

      Ctrl_C : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (3)];
      Last   : Ada.Streams.Stream_Element_Offset;

      --  The sleeper writes its lines and then refuses to finish, which is
      --  what gives an interrupt something to interrupt.
      Hang : Hostkit.String_Vectors.Vector;
   begin
      if not Hostkit.Pty.Is_Supported
        or else not Hostkit.Spawn.Supports_Sessions
        or else not Hostkit.Signals.Is_Supported
                      (Hostkit.Signals.Signal_Interrupt)
      then
         --  Windows: no pseudo-terminals, no sessions of this shape and no
         --  signals. Each is answered for separately because a host could
         --  gain one without the others.
         return;
      end if;

      Hang.Append (Ada.Strings.Unbounded.To_Unbounded_String ("--hang"));

      Assert (Hostkit.Pty.Open (Terminal), "could not open a pseudo-terminal");

      --  Its own session, with this terminal as the controlling one, and its
      --  own group in that terminal's foreground: the three together are what
      --  a keystroke needs to become a signal, and Attach is where they are
      --  arranged.
      Assert (Hostkit.Pty.Attach (Terminal, Options),
              "could not arrange to start a child on a terminal");

      Assert (Hostkit.Spawn.Start
                (Companion ("sleeper"), Hang, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the sleeper would not start on a terminal");

      Hostkit.Pty.Close_Device (Terminal);

      --  It writes a line before it hangs, so waiting for that is waiting for
      --  a child that has reached its own code rather than for a fixed time.
      declare
         Seen : Boolean := False;
      begin
         for Attempt in 1 .. 100 loop
            declare
               Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
               Taken  : Ada.Streams.Stream_Element_Offset;
            begin
               if D.Read (Terminal.From_Child, Buffer, Taken) = D.Transfer_Ok
                 and then Taken >= Buffer'First
               then
                  Seen := True;
                  exit;
               end if;
            end;

            delay 0.05;
         end loop;

         Assert (Seen, "the child never wrote to the terminal it was given");
      end;

      Assert (D.Write (Terminal.To_Child, Ctrl_C, Last) = D.Transfer_Ok,
              "could not type into the terminal");

      for Attempt in 1 .. 100 loop
         if Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
           and then Result.State /= Hostkit.Spawn.Wait_Running
         then
            Ended := True;
            exit;
         end if;

         delay 0.05;
      end loop;

      Assert (Ended and then Result.State = Hostkit.Spawn.Wait_Signalled,
              "Ctrl-C at the terminal did not reach the child: "
              & Hostkit.Spawn.Wait_State'Image (Result.State));

      Hostkit.Pty.Close (Terminal);
   end Test_A_Child_Can_Own_A_Terminal;

   --  A child started on a terminal reads what is typed at it and writes back
   --  through it -- on every host, whatever shape that host's terminal is.
   --
   --  The test that matters most for the newest of the three. Where there are
   --  pseudo-terminals this has always worked and this says so; where the
   --  answer is a pseudo-console, nothing here had ever started a child at all
   --  and the only thing asserted was the refusal. What it does not assert is
   --  *how* the bytes come back: a console host redraws rather than echoing,
   --  so what arrives is the child's text among control sequences, and the
   --  claim is that the text is in there.
   procedure Test_A_Child_Runs_On_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Terminal : Hostkit.Pty.Pair;
      Options  : Hostkit.Spawn.Options;
      Child    : Hostkit.Spawn.Process_Handle;
      Result   : Hostkit.Spawn.Status;
      Nothing  : Hostkit.String_Vectors.Vector;

      --  CR LF, because the two hosts disagree about which one Enter is and
      --  each accepts the pair.
      --  Bounds written out. A positional aggregate for an unconstrained array
      --  starts at the index type's first value, which for a stream element
      --  offset is a large negative number, and every length computed from it
      --  afterwards overflows.
      Typed : constant Ada.Streams.Stream_Element_Array (1 .. 7) :=
        [Character'Pos ('h'), Character'Pos ('e'), Character'Pos ('l'),
         Character'Pos ('l'), Character'Pos ('o'), 13, 10];

      Last : Ada.Streams.Stream_Element_Offset;
      Seen : Unbounded_String;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Terminal), "could not open a terminal");
      Assert (Hostkit.Pty.Set_Size (Terminal, (Rows => 24, Columns => 80)),
              "could not size the terminal");
      Assert (Hostkit.Pty.Attach (Terminal, Options),
              "could not arrange to start a child on the terminal");

      Assert (Hostkit.Spawn.Start
                (Companion ("echoer"), Nothing, Options, Child)
              = Hostkit.Spawn.Spawn_Ok,
              "the echoer would not start on a terminal");

      --  The parent's copy of the child's side, where there was one. While it
      --  holds that open, reading its own side never ends.
      Hostkit.Pty.Close_Device (Terminal);

      --  A moment for the host to attach a client to the terminal, and for
      --  whatever it says when it does. A console host announces itself the
      --  moment it has one; a pseudo-terminal says nothing at all, so this is
      --  a wait that finds something on one host and nothing on the other, and
      --  neither is a failure. What it is for is not typing at a terminal
      --  whose far side is not there yet.
      if D.Wait_Readable (Terminal.From_Child, 500) then
         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 1024);
            Taken  : Ada.Streams.Stream_Element_Offset;
         begin
            if D.Read (Terminal.From_Child, Buffer, Taken) = D.Transfer_Ok
              and then Taken >= Buffer'First
            then
               for Index in Buffer'First .. Taken loop
                  Append (Seen, Character'Val (Natural (Buffer (Index))));
               end loop;
            end if;
         end;
      end if;

      Assert (D.Write (Terminal.To_Child, Typed, Last) = D.Transfer_Ok,
              "could not type into the terminal");

      for Attempt in 1 .. 200 loop
         if D.Wait_Readable (Terminal.From_Child, 50) then
            declare
               Buffer : Ada.Streams.Stream_Element_Array (1 .. 1024);
               Taken  : Ada.Streams.Stream_Element_Offset;
            begin
               if D.Read (Terminal.From_Child, Buffer, Taken) = D.Transfer_Ok
                 and then Taken >= Buffer'First
               then
                  for Index in Buffer'First .. Taken loop
                     Append (Seen, Character'Val (Natural (Buffer (Index))));
                  end loop;
               end if;
            end;
         end if;

         exit when Ada.Strings.Fixed.Index (To_String (Seen), "read:hello") > 0;
      end loop;

      --  How the child ended, gathered before asserting anything about what it
      --  wrote. A child that exited 3 read nothing at all, which is a
      --  different fault from one that read the wrong thing or wrote where
      --  this cannot see it -- and a failure that cannot tell those apart
      --  costs a run to find out.
      declare
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

         Assert (Ada.Strings.Fixed.Index (To_String (Seen), "read:hello") > 0,
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
      for Attempt in 1 .. 20 loop
         exit when not D.Wait_Readable (Terminal.From_Child, 10);

         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 1024);
            Taken  : Ada.Streams.Stream_Element_Offset;
         begin
            exit when D.Read (Terminal.From_Child, Buffer, Taken)
                      /= D.Transfer_Ok;
         end;
      end loop;

      Hostkit.Pty.Close (Terminal);
   end Test_A_Child_Runs_On_A_Terminal;

   procedure Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item : Hostkit.Pty.Pair;
      Size : Hostkit.Terminal_Control.Window_Size;
      --  Set by a call this test requires to refuse, so it is never read.
      pragma Warnings (Off, Size);
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      if D.Is_Valid (Item.Device) then
         --  Fresh, it reports zero by zero, and Size refuses rather than
         --  passing that on -- the single most common way to get a
         --  pseudo-terminal wrong is to hand a child one that says it has no
         --  room. A console is made with a size instead, because the host will
         --  not make one measuring nothing.
         Assert (not Hostkit.Terminal_Control.Size (Item.Device, Size),
                 "an unsized pseudo-terminal reported a size");
      end if;

      Assert (Hostkit.Pty.Set_Size (Item, (Rows => 24, Columns => 80)),
              "could not set the pseudo-terminal size");

      if not D.Is_Valid (Item.Device) then
         --  Nothing to ask on a host with no device side: what the console was
         --  told is between it and the child it redraws.
         Hostkit.Pty.Close (Item);
         return;
      end if;

      Assert (Hostkit.Terminal_Control.Size (Item.Device, Size),
              "a sized pseudo-terminal would not report its size");
      Assert (Size.Rows = 24 and then Size.Columns = 80,
              "the pseudo-terminal reported a size it was not given:"
              & Integer'Image (Size.Rows) & " by" & Integer'Image (Size.Columns));

      Hostkit.Pty.Close (Item);
   end Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set;

   procedure Test_A_Recorded_Signal_Is_Remembered
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      if not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Window_Change) then
         --  A host that cannot record this signal says so rather than
         --  appearing to. Can_Record rather than Is_Supported: recording is
         --  the narrower capability, and this test is about recording.
         Assert (not Hostkit.Signals.Set_Disposition
                   (Hostkit.Signals.Signal_Window_Change,
                    Hostkit.Signals.Disposition_Record),
                 "a host without the signal accepted a disposition for it");
         return;
      end if;

      --  Window_Change rather than Interrupt: a test that arranged to be
      --  interrupted would be one that kills the suite if the disposition does
      --  not take, and this one is harmless whatever happens to it.
      Assert (Hostkit.Signals.Set_Disposition
                (Hostkit.Signals.Signal_Window_Change,
                 Hostkit.Signals.Disposition_Record),
              "the recording disposition was refused");

      --  Nothing yet: installing clears, so a signal that arrived before
      --  anybody was listening is not reported to whoever just started.
      Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
              "a freshly installed recorder already reported an arrival");

      Assert (Hostkit.Signals.Send_To_Process
                (Hostkit.Host.Own_Process_Id, Hostkit.Signals.Signal_Window_Change),
              "the signal could not be sent to this process");

      --  The handler runs between two instructions of this program, so by the
      --  time the send has returned the flag is set. This is the whole
      --  mechanism: a handler may do almost nothing, so it records and the
      --  program asks at a moment of its own choosing.
      Assert (Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
              "a signal that was sent was not recorded");

      --  And it stays recorded until acknowledged: a program that asks twice
      --  must get the same answer, or whether it stops depends on how often
      --  it happened to look.
      Assert (Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
              "asking twice consumed the arrival");

      Hostkit.Signals.Clear (Hostkit.Signals.Signal_Window_Change);
      Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
              "clearing did not forget the arrival");

      --  A signal nobody recorded never arrives, whatever happens to it.
      Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Terminate),
              "a signal with no recorder reported an arrival");

      declare
         Ignored : constant Boolean :=
           Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Window_Change,
              Hostkit.Signals.Disposition_Default);
      begin
         Assert (Ignored or else not Ignored, "unreachable");
      end;
   end Test_A_Recorded_Signal_Is_Remembered;

   procedure Test_Can_Record_Agrees_With_Set_Disposition
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Can_Record is a promise, and this is the test that it is kept. A
      --  caller decides whether to offer Ctrl-C on the strength of it, so a
      --  host answering yes and then refusing the disposition would send that
      --  caller down a path with no way back.
      --
      --  Both directions matter. Answering yes and refusing strands the
      --  caller; answering no and succeeding hides a capability the host has,
      --  which is how a platform ends up permanently poorer than it needs to
      --  be because nobody rechecked.
      for Item in Hostkit.Signals.Signal loop
         declare
            Claimed : constant Boolean := Hostkit.Signals.Can_Record (Item);
            Actual  : constant Boolean :=
              Hostkit.Signals.Set_Disposition (Item, Hostkit.Signals.Disposition_Record);
         begin
            Assert (Claimed = Actual,
                    "Can_Record and Set_Disposition disagree about "
                    & Hostkit.Signals.Name (Item)
                    & ": claimed " & Boolean'Image (Claimed)
                    & ", got " & Boolean'Image (Actual));

            --  Put it back before the next case. Left installed, a recorder on
            --  SIGPIPE or SIGCHLD would change how every later test in this
            --  suite behaves, and the failure would land somewhere else.
            if Actual then
               declare
                  Restored : constant Boolean :=
                    Hostkit.Signals.Set_Disposition
                      (Item, Hostkit.Signals.Disposition_Default);
               begin
                  Assert (Restored,
                          "a signal that accepted a recorder would not go back "
                          & "to its default: " & Hostkit.Signals.Name (Item));
               end;
               Hostkit.Signals.Clear (Item);
            end if;
         end;
      end loop;

      --  The two signals POSIX will not let anyone catch. Named rather than
      --  left to the loop above, because "no host claims these" is the part
      --  that would be wrong to quietly start claiming.
      Assert (not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Kill),
              "a host claimed it could record KILL");
      Assert (not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Stop),
              "a host claimed it could record STOP");
   end Test_Can_Record_Agrees_With_Set_Disposition;

   procedure Test_Cursor_Control_Refuses_A_Pipe
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ends : D.Pipe_Ends;
   begin
      Assert (D.Create_Pipe (Ends), "could not create a pipe");

      --  Nothing may be drawn on something that is not a terminal. A caller
      --  that got True here would write escape bytes into whatever is reading
      --  the pipe, and those bytes would look like data.
      Assert (not Hostkit.Terminal_Control.Supports_Cursor_Control (Ends.Write_End),
              "a pipe claimed to support cursor control");

      for Action in Hostkit.Terminal_Control.Cursor_Action loop
         Assert (not Hostkit.Terminal_Control.Control (Ends.Write_End, Action),
                 "a pipe accepted the cursor action "
                 & Hostkit.Terminal_Control.Cursor_Action'Image (Action));
      end loop;

      D.Close (Ends.Read_End);
      D.Close (Ends.Write_End);
   end Test_Cursor_Control_Refuses_A_Pipe;

   procedure Test_Cursor_Control_Writes_To_A_Pseudo_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item  : Hostkit.Pty.Pair;
      Into  : Ada.Streams.Stream_Element_Array (1 .. 64);
      Last  : Ada.Streams.Stream_Element_Offset;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      if not Has_A_Device_Side (Item) then
         Hostkit.Pty.Close (Item);
         return;
      end if;

      Assert (Hostkit.Terminal_Control.Supports_Cursor_Control (Item.Device),
              "a pseudo-terminal refused cursor control");

      --  A movement of zero writes nothing and is not a failure. A caller that
      --  computed a distance of zero would otherwise emit "move left zero",
      --  which some terminals read as "move left one".
      Assert (Hostkit.Terminal_Control.Control
                (Item.Device, Hostkit.Terminal_Control.Move_Left, 0),
              "a zero-distance move was reported as a failure");

      Assert (Hostkit.Terminal_Control.Control
                (Item.Device, Hostkit.Terminal_Control.Erase_To_End_Of_Line),
              "erase-to-end-of-line was refused by a pseudo-terminal");

      --  Something arrived, and it is not the caller's business what. The point
      --  of the check is that the action reached the terminal at all: an action
      --  that silently wrote nothing would leave a line editor redrawing over
      --  its own previous output.
      case D.Read (Item.From_Child, Into, Last) is
         when D.Transfer_Ok =>
            Assert (Last >= Into'First,
                    "a cursor action wrote no bytes to the terminal");
         when others =>
            Assert (False, "could not read back what the cursor action wrote");
      end case;

      Hostkit.Pty.Close (Item);
   end Test_Cursor_Control_Writes_To_A_Pseudo_Terminal;

   --  A child given a replaced environment sees exactly what it was given.
   --
   --  Nothing tested this, on any host, and Adash's conformance runner leans
   --  on it for every one of its six hundred cases: it replaces the
   --  environment so a case gives the same answer on a developer's machine as
   --  in CI. The Windows body builds an environment block by hand -- one
   --  buffer of NAME=VALUE, each NUL-terminated, a second NUL at the end,
   --  decoded to UTF-16 -- and until this ran, nothing had ever executed that
   --  code and looked at the result.
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

   --  Two saves of a terminal nobody touched in between.
   --
   --  Asked because the round-trip test compares saved settings for equality,
   --  and that only means anything if a save is stable. A saved mode is an
   --  opaque buffer handed back to the host, and a host whose structure has
   --  padding in it can copy out whatever those bytes happened to hold -- in
   --  which case two saves differ, the round-trip test fails, and the restore
   --  it appears to accuse did its job perfectly. This tells the two apart:
   --  if this fails, the comparison is at fault; if this passes and the
   --  round-trip fails, the restore is.
   procedure Test_A_Saved_Mode_Is_Stable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item   : Hostkit.Pty.Pair;
      Once   : Hostkit.Terminal_Control.Mode;
      Again  : Hostkit.Terminal_Control.Mode;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      if not Has_A_Device_Side (Item) then
         Hostkit.Pty.Close (Item);
         return;
      end if;

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Once),
              "could not save the terminal settings");
      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Again),
              "could not save the terminal settings a second time");

      Assert (Once = Again,
              "two saves of an untouched terminal did not agree, so what a "
              & "saved mode holds is not only the settings");

      Hostkit.Pty.Close (Item);
   end Test_A_Saved_Mode_Is_Stable;

   procedure Test_Raw_Mode_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item   : Hostkit.Pty.Pair;
      Before : Hostkit.Terminal_Control.Mode;
      Raw    : Hostkit.Terminal_Control.Mode;
      After  : Hostkit.Terminal_Control.Mode;
      Again  : Hostkit.Terminal_Control.Mode;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      --  Done on a pseudo-terminal rather than on the suite's own standard
      --  input: a test that put the developer's real terminal into raw mode and
      --  then failed an assertion would leave them typing `reset` blind.
      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      if not Has_A_Device_Side (Item) then
         Hostkit.Pty.Close (Item);
         return;
      end if;

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Before),
              "could not save the terminal settings");
      Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
              "could not set raw mode");

      --  Raw is a different terminal from the one that was saved. Asked before
      --  the restore because a Set_Raw that changed nothing would make the
      --  round-trip below pass for the wrong reason -- and on a host where the
      --  round-trip fails, it says whether the going or the coming back is at
      --  fault.
      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Raw),
              "could not read back the raw settings");
      Assert (Before /= Raw,
              "setting raw mode changed nothing this host will admit to");

      Assert (Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before),
              "could not restore the terminal settings");

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, After),
              "could not re-read the terminal settings");

      --  Not `Before = After`. A saved mode holds host state as well as
      --  settings -- macOS keeps PENDIN in it -- so a restore that applied
      --  every setting can still read back as something else, and asserting
      --  byte equality tests the host's state bits rather than this crate.
      --
      --  What is asked instead is that the restore is not a no-op and is
      --  repeatable: it moved the terminal away from raw, and going round
      --  again lands in the same place. A restore that did nothing would leave
      --  After equal to Raw, and one that landed somewhere new each time would
      --  not agree with itself.
      Assert (After /= Raw,
              "restoring left the terminal in raw mode");

      Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
              "could not set raw mode a second time");
      Assert (Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before),
              "could not restore the terminal settings a second time");
      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Again),
              "could not re-read the terminal settings a second time");

      Assert (After = Again,
              "restoring the same saved settings twice reached two different "
              & "terminals");

      Hostkit.Pty.Close (Item);
   end Test_Raw_Mode_Round_Trips;

   --  What the host did not put back, byte by byte.
   --
   --  The round-trip tests say a restore did not restore; this says which byte
   --  and what it became, which is the difference between a mystery and a bug
   --  report. It ignores what Restore_Mode answers on purpose -- that now
   --  refuses when the read-back disagrees, and the point here is to describe
   --  the disagreement rather than to repeat that there is one.
   procedure Test_What_A_Host_Does_Not_Put_Back
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item   : Hostkit.Pty.Pair;
      Before : Hostkit.Terminal_Control.Mode;
      After  : Hostkit.Terminal_Control.Mode;
      Again  : Hostkit.Terminal_Control.Mode;

      Was, Became : Interfaces.Unsigned_8;
      Restored    : Boolean;
      Where       : Natural;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      if not Has_A_Device_Side (Item) then
         Hostkit.Pty.Close (Item);
         return;
      end if;

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Before),
              "could not save the terminal settings");
      Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
              "could not set raw mode");

      Restored := Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before);

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, After),
              "could not re-read the terminal settings");

      --  Round again. What a host may do is keep a state bit of its own -- and
      --  then it keeps the same one every time. What it may not do is lose a
      --  setting, which would show as the two journeys landing in different
      --  places.
      Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
              "could not set raw mode a second time");
      Restored := Restored
        and then Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before);
      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Again),
              "could not re-read the terminal settings a second time");

      Where := Hostkit.Terminal_Control.Differences.First_Difference
                 (Before, After, Was, Became);

      --  The message carries the diagnosis whether or not this host needed
      --  one: a run that fails somewhere else can be read without a second
      --  trip through CI.
      Assert (After = Again,
              "two restores of the same saved settings reached two different"
              & " terminals; the first differs from what was saved at byte"
              & Natural'Image (Where) & ", which was"
              & Interfaces.Unsigned_8'Image (Was) & " and came back as"
              & Interfaces.Unsigned_8'Image (Became)
              & "; Restore_Mode answered " & Boolean'Image (Restored));

      Hostkit.Pty.Close (Item);
   end Test_What_A_Host_Does_Not_Put_Back;

   --  The same journey on the other side of the pair.
   --
   --  A pseudo-terminal has two descriptors and they are not the same kind of
   --  thing: one is what a child sees as its terminal, the other is what the
   --  parent holds. If the settings come back on one and not on the other, what
   --  is at fault is the host's driver for that side rather than this crate's
   --  save and restore -- and that is worth knowing before anything here is
   --  changed to suit it.
   procedure Test_Raw_Mode_Round_Trips_On_The_Controller
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item   : Hostkit.Pty.Pair;
      Before : Hostkit.Terminal_Control.Mode;
      After  : Hostkit.Terminal_Control.Mode;
      Again  : Hostkit.Terminal_Control.Mode;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      if not D.Is_Terminal (Item.From_Child) then
         --  A host whose parent side is a pipe rather than a terminal: there
         --  are no line-discipline settings to save, and asking for them is
         --  what Is_Terminal is for. The console keeps the modes there, and
         --  the child's end of it is what has them.
         Hostkit.Pty.Close (Item);
         return;
      end if;

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.From_Child, Before),
              "could not save the controller's settings");
      Assert (Hostkit.Terminal_Control.Set_Raw (Item.From_Child),
              "could not set raw mode on the controller");
      Assert (Hostkit.Terminal_Control.Restore_Mode (Item.From_Child, Before),
              "could not restore the controller's settings");
      Assert (Hostkit.Terminal_Control.Save_Mode (Item.From_Child, After),
              "could not re-read the controller's settings");

      Assert (Hostkit.Terminal_Control.Set_Raw (Item.From_Child),
              "could not set raw mode on the controller a second time");
      Assert (Hostkit.Terminal_Control.Restore_Mode (Item.From_Child, Before),
              "could not restore the controller's settings a second time");
      Assert (Hostkit.Terminal_Control.Save_Mode (Item.From_Child, Again),
              "could not re-read the controller's settings a second time");

      Assert (After = Again,
              "restoring the controller's settings twice reached two different "
              & "terminals");

      Hostkit.Pty.Close (Item);
   end Test_Raw_Mode_Round_Trips_On_The_Controller;

   procedure Test_An_Unsaved_Mode_Is_Not_Applied
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item   : Hostkit.Pty.Pair;
      Unsaved : Hostkit.Terminal_Control.Mode;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      --  A Mode that was never filled is zeroes, and applying zeroes to a
      --  terminal is worse than leaving it raw: no baud rate, no character
      --  size, no control characters. It has to refuse.
      Assert (not Hostkit.Terminal_Control.Restore_Mode (Item.Device, Unsaved),
              "a terminal mode that was never saved was applied anyway");

      Hostkit.Pty.Close (Item);
   end Test_An_Unsaved_Mode_Is_Not_Applied;

   -----------------------------------------------------------------------
   --  Locks
   -----------------------------------------------------------------------

   procedure Test_An_Exclusive_Lock_Excludes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory,
                                 "hostkit-lock-test.tmp");
      First  : Hostkit.Locks.Lock;
      Second : Hostkit.Locks.Lock;
      Taken  : Hostkit.Locks.Lock_Outcome;
   begin
      Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, First);

      if Taken = Hostkit.Locks.Lock_Unsupported then
         --  A filesystem that does not carry locks. Reported, not pretended.
         return;
      end if;

      Assert (Taken = Hostkit.Locks.Lock_Ok,
              "could not take an exclusive lock: "
              & Hostkit.Locks.Lock_Outcome'Image (Taken));
      Assert (Hostkit.Locks.Is_Held (First), "the lock does not report itself held");

      --  flock is per open file description, so a second Acquire in this same
      --  process opens the file again and genuinely contends. Without this the
      --  lock could be a no-op and nothing above would notice.
      Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Second);
      Assert (Taken = Hostkit.Locks.Lock_Busy,
              "a second exclusive lock was granted: "
              & Hostkit.Locks.Lock_Outcome'Image (Taken));
      Assert (not Hostkit.Locks.Is_Held (Second),
              "a refused lock reported itself held");

      Hostkit.Locks.Release (First);
      Assert (not Hostkit.Locks.Is_Held (First), "Release left the lock held");

      --  And once released it is available again.
      Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Second);
      Assert (Taken = Hostkit.Locks.Lock_Ok,
              "the lock was not available after being released");
      Hostkit.Locks.Release (Second);

      --  Releasing twice must be harmless, like closing a descriptor twice, or
      --  an error path releases something a later Acquire has taken.
      Hostkit.Locks.Release (Second);

      Ada.Directories.Delete_File (Path);
   end Test_An_Exclusive_Lock_Excludes;

   procedure Test_Shared_Locks_Coexist
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory,
                                 "hostkit-lock-shared.tmp");
      First  : Hostkit.Locks.Lock;
      Second : Hostkit.Locks.Lock;
      Taken  : Hostkit.Locks.Lock_Outcome;
   begin
      Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Shared, False, First);

      if Taken = Hostkit.Locks.Lock_Unsupported then
         return;
      end if;

      Assert (Taken = Hostkit.Locks.Lock_Ok, "could not take a shared lock");

      --  Two readers at once is the point of a shared lock. If this refused,
      --  loading state would serialise every session for no reason.
      Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Shared, False, Second);
      Assert (Taken = Hostkit.Locks.Lock_Ok,
              "a second shared lock was refused: "
              & Hostkit.Locks.Lock_Outcome'Image (Taken));

      Hostkit.Locks.Release (First);
      Hostkit.Locks.Release (Second);

      Ada.Directories.Delete_File (Path);
   end Test_Shared_Locks_Coexist;

   procedure Test_Locking_Does_Not_Truncate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path   : constant String :=
        Ada.Directories.Compose (Ada.Directories.Current_Directory,
                                 "hostkit-lock-keeps.tmp");
      Item   : D.Descriptor;
      Sent   : constant Ada.Streams.Stream_Element_Array (1 .. 4) := [100, 97, 116, 97];
      Last   : Ada.Streams.Stream_Element_Offset;
      --  Set by a call whose success is what is asserted, not its result.
      pragma Warnings (Off, Last);
      Held   : Hostkit.Locks.Lock;
      Taken  : Hostkit.Locks.Lock_Outcome;
   begin
      Assert (D.Open_File (Path, D.Open_Write_Truncate, Item), "could not create the file");
      Assert (D.Write (Item, Sent, Last) = D.Transfer_Ok, "could not write the file");
      D.Close (Item);

      Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Held);

      if Taken = Hostkit.Locks.Lock_Ok then
         Hostkit.Locks.Release (Held);
      elsif Taken /= Hostkit.Locks.Lock_Unsupported then
         Assert (False, "could not lock the file: "
                 & Hostkit.Locks.Lock_Outcome'Image (Taken));
      end if;

      --  A lock taken on the state file itself must not destroy the state it is
      --  protecting. Opening with O_TRUNC here would do exactly that, silently,
      --  and only for the caller that locked before reading.
      Assert (Ada.Directories.Size (Path) = 4,
              "taking a lock truncated the file it was protecting");

      Ada.Directories.Delete_File (Path);
   end Test_Locking_Does_Not_Truncate;

   ----------
   -- Name --
   ----------

   Started : Natural := 0;

   overriding procedure Set_Up (T : in out Case_Type) is
      pragma Unreferenced (T);
   begin
      Started := Started + 1;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "-> shell routine" & Natural'Image (Started));
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
   end Set_Up;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("hostkit shell primitives");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_A_Pipe_Carries_Bytes_And_Then_Ends'Access,
         "descriptors : a pipe carries bytes and ends when the writer closes");
      Register_Routine
        (T, Test_Closing_Twice_Is_Harmless'Access,
         "descriptors : closing twice is harmless");
      Register_Routine
        (T, Test_A_File_Round_Trips_Through_A_Descriptor'Access,
         "descriptors : a file round-trips, and an absent one is refused");
      Register_Routine
        (T, Test_A_Childs_Output_Arrives_Down_A_Pipe'Access,
         "spawn : a child's output arrives down a pipe the parent made");
      Register_Routine
        (T, Test_An_Exit_Status_Comes_Back'Access,
         "spawn : an exit status comes back intact");
      Register_Routine
        (T, Test_A_Missing_Program_Is_Told_Apart_From_A_Failing_One'Access,
         "spawn : a missing program is told apart from one that ran and failed");
      Register_Routine
        (T, Test_A_Directory_Is_Not_Executable'Access,
         "spawn : a directory is reported as not executable");
      Register_Routine
        (T, Test_A_Child_Can_Be_Put_In_Its_Own_Group'Access,
         "spawn : a child can lead its own process group");
      Register_Routine
        (T, Test_A_Group_Can_Be_Signalled_As_One'Access,
         "spawn : a whole process group is signalled at once");
      Register_Routine
        (T, Test_A_Child_Reads_The_Input_It_Was_Given'Access,
         "spawn : a child reads the input it was given, through two pipes");
      Register_Routine
        (T, Test_Polling_Reports_A_Child_Still_Running'Access,
         "spawn : a poll reports a running child without blocking");
      Register_Routine
        (T, Test_Signal_Names_And_Numbers_Agree'Access,
         "signals : names and numbers agree and round-trip");
      Register_Routine
        (T, Test_An_Unknown_Signal_Number_Is_Refused'Access,
         "signals : an unknown number is refused, not guessed");
      Register_Routine
        (T, Test_A_Disposition_Round_Trips'Access,
         "signals : a disposition round-trips");
      Register_Routine
        (T, Test_Kill_And_Stop_Cannot_Be_Caught'Access,
         "signals : kill and stop refuse to be ignored");
      Register_Routine
        (T, Test_Signalling_Nothing_Is_Refused'Access,
         "signals : a non-positive process or group id is refused");
      Register_Routine
        (T, Test_A_Pipe_Has_No_Terminal_Answers'Access,
         "terminal : a pipe refuses every terminal question");
      Register_Routine
        (T, Test_A_Pseudo_Terminal_Is_A_Terminal'Access,
         "pty : both sides of a pseudo-terminal are terminals");
      Register_Routine
        (T, Test_A_Child_Can_Own_A_Terminal'Access,
         "pty : a child in its own session is interrupted by Ctrl-C");
      Register_Routine
        (T, Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set'Access,
         "pty : a fresh pseudo-terminal has no size until it is given one");
      Register_Routine
        (T, Test_A_Recorded_Signal_Is_Remembered'Access,
         "signals : a recorded signal is remembered until it is acknowledged");
      Register_Routine
        (T, Test_Can_Record_Agrees_With_Set_Disposition'Access,
         "Can_Record agrees with what Set_Disposition does");
      Register_Routine
        (T, Test_Cursor_Control_Refuses_A_Pipe'Access,
         "terminal : cursor control refuses anything that is not a terminal");
      Register_Routine
        (T, Test_Cursor_Control_Writes_To_A_Pseudo_Terminal'Access,
         "terminal : a cursor action reaches the terminal it is aimed at");
      Register_Routine
        (T, Test_A_Replaced_Environment_Reaches_The_Child'Access,
         "spawn : a replaced environment reaches the child");
      Register_Routine
        (T, Test_A_Saved_Mode_Is_Stable'Access,
         "terminal : two saves of an untouched terminal agree");
      Register_Routine
        (T, Test_Raw_Mode_Round_Trips'Access,
         "terminal : raw mode round-trips and the settings come back");
      Register_Routine
        (T, Test_A_Child_Runs_On_A_Terminal'Access,
         "shell : a child runs on a terminal and reads what is typed at it");
      Register_Routine
        (T, Test_Raw_Mode_Round_Trips_On_The_Controller'Access,
         "terminal : and round-trips on the controller side too");
      Register_Routine
        (T, Test_What_A_Host_Does_Not_Put_Back'Access,
         "terminal : and says which byte a host did not put back");
      Register_Routine
        (T, Test_An_Unsaved_Mode_Is_Not_Applied'Access,
         "terminal : a mode that was never saved is refused, not applied");
      Register_Routine
        (T, Test_An_Exclusive_Lock_Excludes'Access,
         "locks : an exclusive lock excludes, and releases");
      Register_Routine
        (T, Test_Shared_Locks_Coexist'Access,
         "locks : shared locks coexist");
      Register_Routine
        (T, Test_Locking_Does_Not_Truncate'Access,
         "locks : locking a file does not truncate it");
   end Register_Tests;

end Hostkit_Shell_Cases;
