with AUnit.Assertions;

with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Unbounded;

with Hostkit;
with Hostkit.Descriptors;
with Hostkit.Locks;
with Hostkit.Pty;
with Hostkit.Signals;
with Hostkit.Spawn;
with Hostkit.Terminal_Control;

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
      No_Args    : Hostkit.String_Vectors.Vector;
      Line       : constant Ada.Streams.Stream_Element_Array (1 .. 7) :=
        [104, 101, 108, 108, 111, 10, 10];
      Last       : Ada.Streams.Stream_Element_Offset;
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

      if Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Kill) then
         Assert (Hostkit.Signals.Send_To_Process
                   (Hostkit.Spawn.Process_Id (Child), Hostkit.Signals.Signal_Kill),
                 "could not kill the hanging sleeper");
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
      Group : Integer;
      Saved : Hostkit.Terminal_Control.Mode;
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
         --  Windows. The refusal is the correct answer there, and a consumer
         --  degrades on it explicitly rather than on a failed Open.
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");
      Assert (D.Is_Valid (Item.Controller) and then D.Is_Valid (Item.Device),
              "a pseudo-terminal handed back an invalid side");

      --  The whole point of the thing: unlike a pipe, both sides are terminals,
      --  so a program that checks will behave as it does for a user.
      Assert (D.Is_Terminal (Item.Device),
              "the device side of a pseudo-terminal is not a terminal");
      Assert (D.Is_Terminal (Item.Controller),
              "the controller side of a pseudo-terminal is not a terminal");

      Assert (Hostkit.Pty.Device_Name (Item)'Length > 0,
              "a pseudo-terminal could not name its device side");

      Hostkit.Pty.Close (Item);
      Assert (not D.Is_Valid (Item.Controller), "Close left the controller valid");
      Assert (not D.Is_Valid (Item.Device), "Close left the device valid");
   end Test_A_Pseudo_Terminal_Is_A_Terminal;

   procedure Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item : Hostkit.Pty.Pair;
      Size : Hostkit.Terminal_Control.Window_Size;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      --  Fresh, it reports zero by zero, and Size refuses rather than passing
      --  that on -- the single most common way to get a pseudo-terminal wrong
      --  is to hand a child one that says it has no room.
      Assert (not Hostkit.Terminal_Control.Size (Item.Device, Size),
              "an unsized pseudo-terminal reported a size");

      Assert (Hostkit.Pty.Set_Size (Item, (Rows => 24, Columns => 80)),
              "could not set the pseudo-terminal size");

      Assert (Hostkit.Terminal_Control.Size (Item.Device, Size),
              "a sized pseudo-terminal would not report its size");
      Assert (Size.Rows = 24 and then Size.Columns = 80,
              "the pseudo-terminal reported a size it was not given:"
              & Integer'Image (Size.Rows) & " by" & Integer'Image (Size.Columns));

      Hostkit.Pty.Close (Item);
   end Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set;

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
      case D.Read (Item.Controller, Into, Last) is
         when D.Transfer_Ok =>
            Assert (Last >= Into'First,
                    "a cursor action wrote no bytes to the terminal");
         when others =>
            Assert (False, "could not read back what the cursor action wrote");
      end case;

      Hostkit.Pty.Close (Item);
   end Test_Cursor_Control_Writes_To_A_Pseudo_Terminal;

   procedure Test_Raw_Mode_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Item   : Hostkit.Pty.Pair;
      Before : Hostkit.Terminal_Control.Mode;
      After  : Hostkit.Terminal_Control.Mode;
   begin
      if not Hostkit.Pty.Is_Supported then
         return;
      end if;

      --  Done on a pseudo-terminal rather than on the suite's own standard
      --  input: a test that put the developer's real terminal into raw mode and
      --  then failed an assertion would leave them typing `reset` blind.
      Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Before),
              "could not save the terminal settings");
      Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
              "could not set raw mode");
      Assert (Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before),
              "could not restore the terminal settings");

      Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, After),
              "could not re-read the terminal settings");

      --  What was put back is what was taken. Without this the restore could be
      --  a no-op and every test above would still pass.
      Assert (Before = After,
              "restoring the terminal settings did not put back what was saved");

      Hostkit.Pty.Close (Item);
   end Test_Raw_Mode_Round_Trips;

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
        (T, Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set'Access,
         "pty : a fresh pseudo-terminal has no size until it is given one");
      Register_Routine
        (T, Test_Cursor_Control_Refuses_A_Pipe'Access,
         "terminal : cursor control refuses anything that is not a terminal");
      Register_Routine
        (T, Test_Cursor_Control_Writes_To_A_Pseudo_Terminal'Access,
         "terminal : a cursor action reaches the terminal it is aimed at");
      Register_Routine
        (T, Test_Raw_Mode_Round_Trips'Access,
         "terminal : raw mode round-trips and the settings come back");
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
