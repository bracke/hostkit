private with Interfaces;

with Hostkit.Descriptors;
with Hostkit.Signals;

--  Starting a program the way a shell has to start one.
--
--  Hostkit.Process already starts programs, and for its callers that is enough:
--  fire and forget, or run to completion with the output in files. A shell can
--  use neither. It has to hand the child descriptors it made itself -- a pipe
--  end, an opened file -- rather than a path to capture into; put the child in a
--  process group so that Ctrl-C reaches the whole pipeline and not just its
--  first stage; give that group the terminal; hand it an environment it
--  constructed; and then *not* wait, because the job may be a background one and
--  the prompt has to come back.
--
--  Three things here are less obvious than they look.
--
--  Why the child's group is set twice. Both the parent and the child call
--  setpgid, with the same arguments, immediately after the fork. Exactly one of
--  them wins and the other fails harmlessly, and which one wins is a race. Doing
--  it in only one place loses that race some of the time: if the parent hands
--  the terminal to a group the child has not joined yet, the child gets SIGTTIN
--  the first time it reads and stops; if the child execs before the parent sets
--  the group, the parent sets it on a process that is already someone else's
--  program. Every shell does this, and every shell that does it once has an
--  intermittent bug.
--
--  Why "command not found" is distinguishable. After a fork, the child cannot
--  return anything -- it can only exit, and an exit status is indistinguishable
--  from the program having run and failed. So the child inherits a close-on-exec
--  pipe: if exec succeeds the pipe closes and the parent reads end-of-file, and
--  if exec fails the child writes errno down it first. That is the only way a
--  shell can say "command not found" rather than "it exited 127", and 127 is a
--  status a real program is entitled to return.
--
--  Why a child gets its signal dispositions back. A shell ignores SIGINT so that
--  Ctrl-C does not kill it, and a child forked from it inherits that. A child
--  that inherits an ignored SIGINT cannot be interrupted -- the foreground
--  program you cannot Ctrl-C out of. Reset_Signals puts the defaults back
--  between the fork and the exec, and defaults to True because the other choice
--  is almost always a bug.
--
--  One interaction to know about. Hostkit.Process.Launch reaps finished children
--  indiscriminately -- waitpid on any child -- because it has no other way to
--  avoid leaving zombies behind. If a consumer of this package also calls
--  Launch, that reaper can collect a child this package is tracking and Wait
--  will then report Wait_Lost for a process whose status is simply gone. A shell
--  should use this package for everything it starts, and not Launch.
package Hostkit.Spawn is

   --  A process this package started.
   --
   --  Not the process itself: on POSIX the identity is a number the kernel
   --  reuses once the process is reaped, so a handle is meaningful only until
   --  Wait reports it finished.
   type Process_Handle is private;

   --  The handle that is not one.
   Invalid_Process : constant Process_Handle;

   --  @param Item Handle to test.
   --  @return True when Item refers to a process this package started.
   function Is_Valid (Item : Process_Handle) return Boolean;

   --  The host's process id, for a diagnostic or a job listing.
   --
   --  @param Item Handle to inspect.
   --  @return The process id, or -1.
   function Process_Id (Item : Process_Handle) return Integer;

   --  The process group this child ended up in -- what Hostkit.Signals.
   --  Send_To_Group and Hostkit.Terminal_Control want.
   --
   --  @param Item Handle to inspect.
   --  @return The group id, or -1 when the host has no process groups.
   function Group_Id (Item : Process_Handle) return Integer;

   --  Which process group a child joins.
   type Group_Policy is
     (
      --  The parent's. Right for a helper the shell runs for itself, wrong for
      --  anything a user can interrupt.
      Group_Inherit,

      --  A new group, led by this child. The first stage of a pipeline.
      Group_New,

      --  An existing group, named by Join_Group. Every stage of a pipeline
      --  after the first, so that one Ctrl-C reaches all of them.
      Group_Join);

   --  How to start a child.
   type Options is record

      --  Where to run it. The parent's directory when empty. Set in the child,
      --  so the shell's own directory is untouched -- a shell that chdir'd
      --  before forking would have to chdir back, and would be in the wrong
      --  place if the fork failed in between.
      Working_Directory : UString := Ada.Strings.Unbounded.Null_Unbounded_String;

      --  What the child gets as its standard streams. Invalid means "the
      --  parent's own", which is what an ordinary foreground command wants.
      Input        : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;
      Output       : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;
      Error_Output : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;

      --  Process group placement.
      Group      : Group_Policy := Group_Inherit;
      Join_Group : Integer := 0;

      --  When valid, the child's group is made this terminal's foreground group
      --  before it execs -- so a foreground job can read the keyboard and
      --  receive Ctrl-C. Done in the child as well as by the caller, for the
      --  race described in the header.
      Foreground_Terminal : Hostkit.Descriptors.Descriptor :=
        Hostkit.Descriptors.Invalid;

      --  When valid, the child starts a session of its own and takes this
      --  terminal as its controlling terminal.
      --
      --  A terminal turns Ctrl-C into a signal for the foreground process
      --  group of the session that *controls* it. A child handed a
      --  pseudo-terminal as its streams does not control it -- the terminal
      --  belongs to whatever session opened it, usually the caller's, and the
      --  caller's own controlling terminal is somewhere else entirely. So a
      --  program run that way cannot be interrupted through the terminal it is
      --  reading from, however its process group is arranged, and
      --  Foreground_Terminal on its own does not help: tcsetpgrp on a terminal
      --  the caller does not control is refused by the host.
      --
      --  What this is for is the program that runs another *under* a terminal
      --  it made: a test harness, a terminal multiplexer, anything that has to
      --  drive an interactive program the way a person would.
      --
      --  Not the default, and it should not be. A session leader starts with
      --  no controlling terminal, so a child that started a session would lose
      --  the one it inherited -- and an ordinary command wants to keep it.
      --
      --  Windows has no sessions in this sense: Supports_Sessions is False
      --  there and Start refuses rather than starting a child that would be
      --  interruptible on one host and not another.
      Controlling_Terminal : Hostkit.Descriptors.Descriptor :=
        Hostkit.Descriptors.Invalid;

      --  Put every signal disposition back to the host default before exec.
      --  See the header: the other choice is almost always a bug.
      Reset_Signals : Boolean := True;

      --  Replace the environment rather than inherit it. When False,
      --  Environment is ignored and the child gets the parent's.
      Replace_Environment : Boolean := False;

      --  The child's environment, one "NAME=VALUE" per element. Used only when
      --  Replace_Environment.
      --
      --  PATH is taken from here too, not from the parent's: a command run with
      --  a modified PATH must be looked up with it, which is what a user who
      --  set it meant.
      Environment : String_Vectors.Vector := String_Vectors.Empty_Vector;
   end record;

   --  What became of the attempt to start a program.
   type Spawn_Outcome is
     (
      --  It started. Whether it then worked is a separate question, answered
      --  by Wait.
      Spawn_Ok,

      --  No such program on PATH, or the path given does not exist. The
      --  shell's "command not found", and conventionally exit status 127.
      Spawn_Not_Found,

      --  It exists but is not something this host can execute -- a directory, a
      --  data file, a script naming an interpreter that is not installed.
      --  Conventionally exit status 126.
      Spawn_Not_Executable,

      --  It exists and is executable, but not by this user.
      Spawn_Denied,

      --  The host refused for some other reason: out of processes, out of
      --  memory, a working directory that does not exist.
      Spawn_Failed);

   --  Start a program.
   --
   --  The caller keeps its own copies of any descriptors it passed and must
   --  close them itself once this returns -- that close is what lets a pipe's
   --  reader eventually see end-of-file. This package cannot do it: it does not
   --  know whether the caller means to hand the same descriptor to the next
   --  stage of a pipeline.
   --
   --  Arguments are a vector and never a command line, so an argument
   --  containing a space, a quote or a newline is just an argument.
   --
   --  Whether this host can start a child in a session of its own, with a
   --  terminal of the caller's as its controlling terminal.
   --
   --  False on Windows, where a console is attached rather than controlled and
   --  there is nothing this shape to ask for. A caller that needs it asks
   --  first; one that sets Controlling_Terminal anyway is refused rather than
   --  quietly given a child that cannot be interrupted.
   --
   --  @return True when Options.Controlling_Terminal is honoured.
   function Supports_Sessions return Boolean;

   --  @param Program The program: a path, or a name to find on PATH.
   --  @param Arguments Its arguments, not including the program name itself.
   --  @param With_Options How to start it.
   --  @param Item The handle, valid only when this returns Spawn_Ok.
   --  @return What became of the attempt. Spawn_Failed when
   --          Controlling_Terminal was set and Supports_Sessions is False:
   --          the caller asked for something this host cannot do, which is a
   --          refusal rather than a silent difference in behaviour.
   function Start
     (Program      : String;
      Arguments    : String_Vectors.Vector;
      With_Options : Options;
      Item         : out Process_Handle) return Spawn_Outcome;

   --  What a process is doing, or what it did.
   type Wait_State is
     (
      --  Still running. Only ever reported by a polling wait.
      Wait_Running,

      --  Finished of its own accord; see Exit_Code.
      Wait_Exited,

      --  Killed by a signal; see Terminating_Signal. Distinct from Wait_Exited
      --  on purpose: a program killed by SIGSEGV did not "exit 139", and a
      --  shell that reports it as an exit status hides how it died.
      Wait_Signalled,

      --  Stopped, and resumable. Ctrl-Z, or SIGSTOP. The process still exists.
      Wait_Stopped,

      --  Resumed after being stopped.
      Wait_Continued,

      --  It is gone and the host cannot say how -- most often because
      --  something else reaped it. See the note about Hostkit.Process.Launch in
      --  the header.
      Wait_Lost);

   --  What a wait found.
   type Status is record
      State : Wait_State := Wait_Running;

      --  Meaningful when State is Wait_Exited.
      Exit_Code : Integer := -1;

      --  Meaningful when State is Wait_Signalled or Wait_Stopped, and only when
      --  Signal_Known -- a host signal this crate does not name leaves the
      --  number in Raw_Signal_Number and Signal_Known False, rather than being
      --  mapped to a signal it is not.
      Terminating_Signal : Hostkit.Signals.Signal := Hostkit.Signals.Signal_Terminate;
      Signal_Known       : Boolean := False;
      Raw_Signal_Number  : Integer := 0;
   end record;

   --  Whether a wait may block.
   type Wait_Mode is
     (
      --  Wait until the process changes state. For a foreground job.
      Wait_Block,

      --  Report what has already happened and return at once. For a shell
      --  refreshing its job table before printing a prompt.
      Wait_Poll);

   --  Ask what became of a process.
   --
   --  Reports stops and continuations, not only exits: without them a shell
   --  cannot tell a job that is waiting from one that has finished, and Ctrl-Z
   --  looks like the program vanished.
   --
   --  @param Item Process to ask about.
   --  @param Mode Whether to block.
   --  @param Result What was found.
   --  @return True when the host answered. False means the handle was invalid
   --          or the host refused the question.
   function Wait
     (Item   : Process_Handle;
      Mode   : Wait_Mode;
      Result : out Status) return Boolean;

   --  Ask what became of any child that has changed state.
   --
   --  What a shell calls before a prompt, to find the background job that
   --  finished while the user was typing. Reports one child per call; call
   --  again until it returns False.
   --
   --  @param Mode Whether to block.
   --  @param Which The child that changed state.
   --  @param Result What was found.
   --  @return True when a child had something to report.
   function Wait_Any
     (Mode   : Wait_Mode;
      Which  : out Process_Handle;
      Result : out Status) return Boolean;

private

   use type Interfaces.Integer_64;

   type Process_Handle is record
      --  The host's process id. Wide enough for a Windows process id or handle
      --  as well as a POSIX pid.
      Id : Interfaces.Integer_64 := -1;

      --  The group it was placed in, or -1 where the host has no groups.
      Group : Interfaces.Integer_64 := -1;
   end record;

   Invalid_Process : constant Process_Handle := (Id => -1, Group => -1);

end Hostkit.Spawn;
