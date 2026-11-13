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
with Hostkit.Fs;
with Hostkit.Limits;
with Hostkit.Locks;
with Hostkit.Microphone;
with Hostkit.Pty;
with Hostkit.Host;
with Hostkit.Process;
with Hostkit.Signals;
with Hostkit.Spawn;
with Hostkit.Terminal_Control;
with Hostkit.Terminal_Control.Differences;

with Hostkit_Test_Skips;

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
   use type Hostkit.Microphone.Outcome;
   use type Hostkit.Microphone.Source_Answer;
   use type Hostkit.Terminal_Control.Mode;
   use type Ada.Directories.File_Size;

   package D renames Hostkit.Descriptors;

   --  A test with nothing to check on this host says so, and is counted:
   --  see Hostkit_Test_Skips.
   procedure Skip (Test : String; Reason : String) renames Hostkit_Test_Skips.Skip;

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
   is separate;

   procedure Test_A_Pipe_Wait_Tells_A_Timeout_From_A_Failure
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Closing_Twice_Is_Harmless
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_File_Round_Trips_Through_A_Descriptor
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   -----------------------------------------------------------------------
   --  Spawning
   -----------------------------------------------------------------------

   procedure Test_A_Childs_Output_Arrives_Down_A_Pipe
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_An_Exit_Status_Comes_Back
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A detached launch collects only its own children. Launch's reaper once
   --  waited for any child, so a spawned child that finished beside a launched
   --  one lost its status to it, and Wait answered Wait_Lost.
   procedure Test_A_Launch_Leaves_A_Spawned_Childs_Status_Alone
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Missing_Program_Is_Told_Apart_From_A_Failing_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Directory_Is_Not_Executable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Child_Can_Be_Put_In_Its_Own_Group
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Group_Can_Be_Signalled_As_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Child_Reads_The_Input_It_Was_Given
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A process is there while it runs and gone once reaped, and this one is there. Where
   --  the host cannot look, every answer is Unknown -- never a guess either way.
   procedure Test_Presence_Follows_A_Process
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Polling_Reports_A_Child_Still_Running
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   -----------------------------------------------------------------------
   --  Signals
   -----------------------------------------------------------------------

   procedure Test_Signal_Names_And_Numbers_Agree
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_An_Unknown_Signal_Number_Is_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Disposition_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Kill_And_Stop_Cannot_Be_Caught
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Signalling_Nothing_Is_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   -----------------------------------------------------------------------
   --  Terminal control and pseudo-terminals
   -----------------------------------------------------------------------

   procedure Test_A_Pipe_Has_No_Terminal_Answers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Pseudo_Terminal_Is_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

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
   is separate;

   --  What a write to a terminal does once nothing holds the device side.
   --
   --  Pty.Write_Fails_When_Unheld is the claim, and this is where it is
   --  measured. A child is started on a terminal, the parent lets go of the
   --  device side, the child is waited for -- so that by the time the byte is
   --  written there is provably nothing on the other end -- and then one byte
   --  is written.
   --
   --  Recorded as well as asserted. Which way a host answers is the fact
   --  worth having in the log of a run on a host nobody develops on, and a
   --  case that only asserted would print nothing on the two hosts that agree
   --  with it and an assertion message on the third.
   --  The creation mask, where the host has one.
   --
   --  POSIX has it and Windows has not, and the difference is the whole reason
   --  this is in this crate: a shell that wants to expose `umask` needs to be
   --  told which kind of host it is on rather than discovering it from a call
   --  that answered zero.
   --
   --  Set, read back, and put back, because reading is the operation POSIX
   --  does not have: umask() sets and returns the previous value together, so
   --  reading means setting twice, and a test that did not restore what it
   --  found would change the permissions of every file the rest of this suite
   --  writes.
   procedure Test_The_Creation_Mask_Is_The_Hosts_Own
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_The_Creation_Mask_Is_The_Hosts_Own
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Assigning a stream moves this program's own writing, not only a child's.
   --
   --  The half that is easy to get wrong on one host: POSIX has dup2, which
   --  moves the descriptor every writer already holds, and Windows keeps two
   --  things -- the standard handle a child is given, and the runtime
   --  descriptor this program writes through. Moving the first alone leaves
   --  every Put_Line where it was, which a consumer found the hard way: its
   --  own line on the console with the file it had redirected to empty.
   --
   --  So this writes through the language's own output, which is the thing a
   --  caller redirecting itself cares about, and reads the file back.
   --
   --  The stream is put back before anything is asserted. A suite that lost
   --  its standard output half way through would report nothing about
   --  anything.
   procedure Test_Assign_Moves_This_Programs_Own_Writing
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Assign_Moves_This_Programs_Own_Writing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Another user's home directory is the host's to answer, or refuse.
   --
   --  Asked about this user by name, because that is the one account a test
   --  can be sure exists: the answer must match what Home_Directory says.
   --  A name nobody has answers "", and so does every name on Windows -- where
   --  a profile folder belongs to whoever is logged in and there is no
   --  supported way to ask about another account.
   procedure Test_Another_Users_Home_Is_The_Hosts_To_Answer
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Another_Users_Home_Is_The_Hosts_To_Answer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A resource limit is the host's own, or the host says it has none.
   --
   --  Open_Files, because it is the limit every POSIX host has a real number
   --  for and the one a shell is most often asked to raise. Lowered rather
   --  than raised: lowering a soft limit needs no privilege anywhere, raising
   --  it past what the runner's hard limit happens to be would fail for a
   --  reason that is about the runner and not about this library.
   --
   --  Put back at the end, because the rest of this suite opens files.
   procedure Test_A_Resource_Limit_Is_The_Hosts_Own
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_A_Resource_Limit_Is_The_Hosts_Own
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The open-file limit is the one that stops a file from opening.
   --
   --  What the reading tests cannot catch is a table that names the right
   --  resources in the wrong order: getrlimit answers happily about whichever
   --  resource the number it was given belongs to, so a transposed entry reads
   --  and sets and looks like everything working. This one lowers the limit
   --  and then opens files until the host refuses, which only happens if the
   --  number really was the one that counts descriptors.
   --
   --  The limit is put back before anything is asserted. A suite that ran the
   --  rest of its cases with sixteen descriptors would fail in places that
   --  have nothing to do with this.
   procedure Test_The_Open_File_Limit_Is_What_Stops_An_Open
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_The_Open_File_Limit_Is_What_Stops_An_Open
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  Every limit this library names is one this host answers about.
   --
   --  The numbers behind the names differ between hosts, and a wrong number is
   --  not an error to the host: getrlimit on a resource that does not exist
   --  answers EINVAL, but a number that belongs to another resource answers
   --  successfully about the wrong thing. What this can check is that every
   --  name reads, which a transposed table would fail.
   procedure Test_Every_Named_Limit_Is_Answered
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Every_Named_Limit_Is_Answered
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Write_To_A_Terminal_Nothing_Holds
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_A_Write_To_A_Terminal_Nothing_Holds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A child started on a terminal writes back through it, and reads what is
   --  typed at it -- on every host, whatever shape that host's terminal is.
   --
   --  The test that matters most for the newest of the three. Where there are
   --  pseudo-terminals this has always worked and this says so; where the
   --  answer is a pseudo-console, nothing here had ever started a child at all
   --  and the only thing asserted was the refusal.
   --
   --  Two children, because the two directions fail differently and a test
   --  that could not say which had failed cost a run each time to find out.
   --  The first writes as soon as it starts and then hangs, so what it proves
   --  is that the child's output reaches the parent's side. The second reads a
   --  line and writes back what it read, which needs the other direction as
   --  well.
   --
   --  What neither asserts is *how* the bytes come back: a console host
   --  redraws where a line discipline echoes, so what arrives is the child's
   --  text among control sequences, and the claim is that the text is in
   --  there.
   --  What the host will *start* from a name is narrower than what it calls a
   --  program, and not narrower in the way one would guess.
   --
   --  On Windows a .bat, a .cmd, a .ps1 and an .msi are all executables. The
   --  first two are started -- the host runs the command interpreter for them
   --  itself -- and the last two are not: one is read by another shell and the
   --  other by the installer. This crate said none of the four were startable
   --  until a case on that host proved otherwise, which is the reason the
   --  question is asked here rather than reasoned about.
   procedure Test_What_Starts_Is_Narrower_Than_What_Runs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Child_Runs_On_A_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Recorded_Signal_Is_Remembered
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_A_Taken_Signal_Is_Gone_And_A_Replaced_Disposition_Is_Said
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_The_Usable_Processors_Include_This_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Can_Record_Agrees_With_Set_Disposition
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Cursor_Control_Refuses_A_Pipe
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Cursor_Control_Writes_To_A_Pseudo_Terminal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

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
   is separate;

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
   is separate;

   procedure Test_Raw_Mode_Round_Trips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  What the host did not put back, byte by byte.
   --
   --  The round-trip tests say a restore did not restore; this says which byte
   --  and what it became, which is the difference between a mystery and a bug
   --  report. It ignores what Restore_Mode answers on purpose -- that now
   --  refuses when the read-back disagrees, and the point here is to describe
   --  the disagreement rather than to repeat that there is one.
   procedure Test_What_A_Host_Does_Not_Put_Back
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

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
   is separate;

   procedure Test_An_Unsaved_Mode_Is_Not_Applied
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   -----------------------------------------------------------------------
   --  Locks
   -----------------------------------------------------------------------

   procedure Test_An_Exclusive_Lock_Excludes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  A program this one starts does not get the lock: one that outlived
   --  this session would hold the file for nobody.
   procedure Test_A_Lock_Is_Not_Inherited
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Shared_Locks_Coexist
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   procedure Test_Locking_Does_Not_Truncate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

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

   --  An exit code this host cannot hold in the shape the other two use.
   --
   --  Windows exit codes are unsigned and thirty-two bits wide, and the ones
   --  the system itself uses sit at the top of that range -- a process ended
   --  by the console control path exits with 0xC000013A. Converting one of
   --  those to Integer overflows, and this crate used to raise rather than
   --  answer: a wait that raises leaves a caller unable to find out that its
   --  child is gone, which is the one thing a wait is for.
   --
   --  A program that ends with -1 is the cheapest way to reach that range: on
   --  Windows it becomes 0xFFFFFFFF and comes back as -1, read as two's
   --  complement the way every tool there shows it. On POSIX the same request
   --  is masked to a byte and comes back as 255, which is what that host does
   --  with a negative status and is asserted rather than papered over.
   procedure Test_An_Exit_Code_Comes_Back_Readable
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_An_Exit_Code_Comes_Back_Readable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  End_Now hands over a status and stops, without unwinding.
   --
   --  The one failure a program cannot clean up after is having nowhere to
   --  write, and Ada's own way out runs finalization -- which closes the
   --  standard files, which flushes them, which fails again. A consumer that
   --  had carefully said nothing then says PROGRAM_ERROR and a stack trace.
   --
   --  What a case can watch is the status arriving from a program that ended
   --  through this rather than by returning, which is what this does. The
   --  companion writes a line first, so a run that produced nothing at all is
   --  told apart from one that reached the call.
   procedure Test_End_Now_Hands_Over_A_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_End_Now_Hands_Over_A_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   --  The claim Interrupt_Reaches_A_Busy_Program makes, on whichever host is
   --  running it.
   --
   --  A program that is *waiting* is told about Ctrl-C everywhere, so waiting
   --  measures nothing: what separates the hosts is a program that is busy.
   --  The companion spins on a terminal that was asked to report an interrupt
   --  and writes down whether it was ever told -- and asks once more half a
   --  second after it stops, because "late" and "never" are different facts
   --  and only one of them can be worked around by looking again.
   --
   --  Asserted against what this crate says rather than against a fixed
   --  answer. A host whose behaviour changed under us would fail here, which
   --  is the point: the function is a promise to callers who build a whole
   --  arrangement on it.
   procedure Test_A_Busy_Program_Is_Told_When_This_Crate_Says_It_Is
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_A_Busy_Program_Is_Told_When_This_Crate_Says_It_Is
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("hostkit shell primitives");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   --  A microphone opens or says why not, never both and never neither: a
   --  host that cannot record answers Unsupported and is not open; a read
   --  of a device never opened fails rather than handing back silence as
   --  though it were recorded. Whether one opens depends on the machine --
   --  a CI runner has no sound server -- so what is held is the agreement.
   procedure Test_A_Microphone_Opens_Or_Says_Why_Not
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is separate;

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_A_Microphone_Opens_Or_Says_Why_Not'Access,
         "microphone : a microphone opens or says why not, and a closed one does not read");
      Register_Routine
        (T, Test_A_Pipe_Carries_Bytes_And_Then_Ends'Access,
         "descriptors : a pipe carries bytes and ends when the writer closes");
      Register_Routine
        (T, Test_A_Pipe_Wait_Tells_A_Timeout_From_A_Failure'Access,
         "descriptors : a wait tells a timeout from a failure");
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
        (T, Test_A_Launch_Leaves_A_Spawned_Childs_Status_Alone'Access,
         "spawn : a launch leaves a spawned child's status alone");
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
        (T, Test_Presence_Follows_A_Process'Access,
         "a process is there while it runs and gone once reaped");
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
        (T, Test_The_Creation_Mask_Is_The_Hosts_Own'Access,
         "the creation mask is the host's own, or the host says it has none");
      Register_Routine
        (T, Test_Assign_Moves_This_Programs_Own_Writing'Access,
         "assigning a stream moves this program's own writing");
      Register_Routine
        (T, Test_Another_Users_Home_Is_The_Hosts_To_Answer'Access,
         "another user's home directory is the host's to answer, or refuse");
      Register_Routine
        (T, Test_A_Resource_Limit_Is_The_Hosts_Own'Access,
         "a resource limit is the host's own, or the host says it has none");
      Register_Routine
        (T, Test_The_Open_File_Limit_Is_What_Stops_An_Open'Access,
         "the open-file limit is the one that stops a file from opening");
      Register_Routine
        (T, Test_Every_Named_Limit_Is_Answered'Access,
         "every limit this library names is one this host answers about");
      Register_Routine
        (T, Test_A_Write_To_A_Terminal_Nothing_Holds'Access,
         "a write to a terminal nothing holds is answered as this host says");
      Register_Routine
        (T, Test_A_Pseudo_Terminal_Is_A_Terminal'Access,
         "pty : both sides of a pseudo-terminal are terminals");
      Register_Routine
        (T, Test_A_Child_Can_Own_A_Terminal'Access,
         "pty : a child in its own session is interrupted by Ctrl-C");
      Register_Routine
        (T, Test_An_Exit_Code_Comes_Back_Readable'Access,
         "process : an exit code comes back readable rather than raising");
      Register_Routine
        (T, Test_End_Now_Hands_Over_A_Status'Access,
         "process : End_Now hands over a status and stops");
      Register_Routine
        (T, Test_A_Busy_Program_Is_Told_When_This_Crate_Says_It_Is'Access,
         "signals : a busy program is told exactly when this crate says");
      Register_Routine
        (T, Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set'Access,
         "pty : a fresh pseudo-terminal has no size until it is given one");
      Register_Routine
        (T, Test_A_Recorded_Signal_Is_Remembered'Access,
         "signals : a recorded signal is remembered until it is acknowledged");
      Register_Routine
        (T, Test_A_Taken_Signal_Is_Gone_And_A_Replaced_Disposition_Is_Said'Access,
         "signals : a taken signal is gone, and a replaced disposition is said");
      Register_Routine
        (T, Test_The_Usable_Processors_Include_This_One'Access,
         "host : the usable processors include at least this one");
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
        (T, Test_What_Starts_Is_Narrower_Than_What_Runs'Access,
         "fs : what the host starts is narrower than what it calls a program");
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
        (T, Test_A_Lock_Is_Not_Inherited'Access,
         "locks : a program started while a lock is held does not get it");
      Register_Routine
        (T, Test_Shared_Locks_Coexist'Access,
         "locks : shared locks coexist");
      Register_Routine
        (T, Test_Locking_Does_Not_Truncate'Access,
         "locks : locking a file does not truncate it");
   end Register_Tests;

end Hostkit_Shell_Cases;
