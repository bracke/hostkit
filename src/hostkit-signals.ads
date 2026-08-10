--  Signals: sending them, and deciding what this process does about them.
--
--  A shell needs signals in three ways, and they are three different questions.
--
--  It sends them. Stopping a job, continuing it, terminating it, hanging it up
--  on exit -- all are a signal to a *process group*, not to a process. Sending
--  to the leader alone stops the leader and leaves the rest of the pipeline
--  running, which looks like Ctrl-Z half-working.
--
--  It refuses some of its own. A shell that dies on Ctrl-C is not a shell, so it
--  ignores SIGINT, SIGQUIT and SIGTSTP for itself and lets the foreground job's
--  process group receive them from the terminal instead. It must also ignore
--  SIGTTOU, or the very call that hands the terminal to a job stops the shell
--  that is making it.
--
--  And one it must refuse or die: SIGPIPE. Writing to a pipe whose reader has
--  gone kills the writer by default. For an ordinary program that is a
--  convenience; for a shell it is fatal, because `something | head -1` makes it
--  happen on purpose. With SIGPIPE ignored the write returns EPIPE instead and
--  Hostkit.Descriptors.Write reports Transfer_Broken_Pipe. Nothing else in this
--  crate works around it, and a consumer that skips it will lose the shell to
--  the first truncated pipeline.
--
--  What is here is the mechanism. Which signals a shell ignores, and when, is
--  policy and belongs to the consumer.
--
--  Windows has none of this. It has no signals, no process groups in the POSIX
--  sense, and no way to ask a process to stop that the process can decline.
--  Every operation here reports its refusal rather than pretending, and
--  Is_Supported says so in advance -- see Hostkit.Process.Request_Stop for what
--  Windows can do instead, which is to terminate a process outright.
package Hostkit.Signals is

   --  The signals a shell has reason to name.
   --
   --  Deliberately not "every signal this host defines". A portable enumeration
   --  of all of them would be a lie on some host; these are the ones whose
   --  meaning is the same wherever they exist.
   type Signal is
     (
      --  Interrupt: the terminal's Ctrl-C. Delivered to the foreground group.
      Signal_Interrupt,

      --  Quit: Ctrl-\. Like interrupt, but conventionally dumps core.
      Signal_Quit,

      --  Polite termination. The process may catch it and clean up.
      Signal_Terminate,

      --  Termination that cannot be caught, blocked or ignored. What a shell
      --  falls back to when asking did not work.
      Signal_Kill,

      --  The terminal went away. A shell sends this to its jobs when it exits.
      Signal_Hangup,

      --  Stop, uncatchable. The counterpart of Signal_Continue.
      Signal_Stop,

      --  Terminal stop: Ctrl-Z. Catchable, unlike Signal_Stop, which is why the
      --  terminal sends this one and not that one.
      Signal_Terminal_Stop,

      --  Resume a stopped process. What `fg` and `bg` send.
      Signal_Continue,

      --  Wrote to a pipe with no reader. See the header above.
      Signal_Pipe,

      --  A background process tried to read from the terminal.
      Signal_Background_Read,

      --  A background process tried to write to the terminal, or to change its
      --  settings. A shell must ignore this one while it calls
      --  Hostkit.Terminal_Control.Set_Foreground_Group, or it stops itself.
      Signal_Background_Write,

      --  The terminal's size changed. An interactive frontend redraws on it.
      Signal_Window_Change,

      --  A child changed state. Available for a consumer that would rather be
      --  told than poll.
      Signal_Child);

   --  Whether this host has this signal at all.
   --
   --  False everywhere on Windows. False is a refusal to guess, not a failure
   --  to be retried, and a consumer that stores it as "not needed here" has
   --  rebuilt the bug this crate exists to prevent.
   --
   --  @param Item Signal to ask about.
   --  @return True when the host defines it.
   function Is_Supported (Item : Signal) return Boolean;

   --  The host's number for a signal, for a diagnostic that has to name one.
   --
   --  Numbers differ between hosts -- SIGUSR1 is 10 on Linux and 30 on macOS --
   --  which is exactly why a consumer should carry the enumeration and call
   --  this only when printing.
   --
   --  @param Item Signal to number.
   --  @return The host's number, or -1 when the host does not define it.
   function Number (Item : Signal) return Integer;

   --  The signal a host number names, for decoding a wait status.
   --
   --  @param Value The host's signal number.
   --  @param Item The signal, meaningful only when this returns True.
   --  @return True when the number names a signal this package knows.
   function From_Number (Value : Integer; Item : out Signal) return Boolean;

   --  A stable, host-independent name, for a message that has to say which
   --  signal ended a job. ASCII, uppercase, without the "SIG" prefix:
   --  "INTERRUPT", "TERMINATE", "KILL".
   --
   --  Not the host's own spelling, and not localized -- this is an identifier a
   --  consumer maps to a message, not text for a user.
   --
   --  @param Item Signal to name.
   --  @return Its name.
   function Name (Item : Signal) return String;

   --  Send a signal to one process.
   --
   --  @param Process_Id The process, as Hostkit.Spawn reported it.
   --  @param Item Signal to send.
   --  @return True when the signal was delivered. False when the host has no
   --          signals, the process is gone, or this process may not signal it.
   function Send_To_Process (Process_Id : Integer; Item : Signal) return Boolean;

   --  Send a signal to every process in a group.
   --
   --  This, not Send_To_Process, is what job control needs. A pipeline is a
   --  group; stopping only its leader leaves the rest running and looks like a
   --  shell whose Ctrl-Z half works.
   --
   --  @param Group_Id The process group, as Hostkit.Spawn reported it.
   --  @param Item Signal to send.
   --  @return True when the signal was delivered.
   function Send_To_Group (Group_Id : Integer; Item : Signal) return Boolean;

   --  What this process does when a signal arrives.
   type Disposition is
     (
      --  Whatever the host does by default -- for most of these, die.
      Disposition_Default,

      --  Discard it. The shell's answer for SIGINT, SIGQUIT, SIGTSTP, SIGTTOU
      --  and, above all, SIGPIPE.
      Disposition_Ignore);

   --  Set what this process does about a signal.
   --
   --  Signal_Kill and Signal_Stop cannot be changed, on any host; asking
   --  returns False rather than appearing to succeed.
   --
   --  A child started through Hostkit.Spawn with Reset_Signals gets the
   --  defaults back before it execs. Without that, a child would inherit the
   --  shell's ignored SIGINT and become unkillable by Ctrl-C -- the bug where
   --  a long-running program in the foreground cannot be interrupted.
   --
   --  @param Item Signal to change.
   --  @param To What to do about it.
   --  @return True when the disposition was set.
   function Set_Disposition (Item : Signal; To : Disposition) return Boolean;

   --  What this process currently does about a signal.
   --
   --  @param Item Signal to ask about.
   --  @param To The current disposition, meaningful only when this returns True.
   --  @return True when the host could answer.
   function Current_Disposition (Item : Signal; To : out Disposition) return Boolean;

end Hostkit.Signals;
