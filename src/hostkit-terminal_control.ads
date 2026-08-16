private with Interfaces;

with Hostkit.Descriptors;

--  The terminal, from the shell's own side: who owns it, how it is set, how big
--  it is.
--
--  Hostkit.Spawn already hands the terminal to a child it starts, because the
--  handover has to happen between the fork and the exec and only that package is
--  there. This is the other three quarters of the job -- the calls a shell makes
--  for itself, before and after a job runs.
--
--  Terminal ownership. A terminal has exactly one foreground process group, and
--  it is the one that receives Ctrl-C and is allowed to read the keyboard.
--  Running a foreground job means giving that group away and taking it back
--  afterwards; every other job runs in the background precisely by not having
--  it.
--
--  The trap in taking it back is SIGTTOU. A process that is not in the
--  foreground group and calls Set_Foreground_Group is sent SIGTTOU, whose
--  default action is to stop it -- so a shell reclaiming its own terminal stops
--  itself, and the user sees the shell freeze when a job finishes. The shell has
--  to ignore SIGTTOU around the call. This package cannot do that for the
--  caller: the disposition is process-wide, and a package that changed it behind
--  a consumer's back would be deciding policy. Hostkit.Signals.Set_Disposition
--  is the call, Signal_Background_Write is the signal, and it is the consumer's
--  to make.
--
--  Modes. A line editor needs the terminal raw: no line buffering, no echo, no
--  interpretation of Ctrl-C into a signal. What it must never do is leave it
--  that way. Save_Mode before, Restore_Mode after, including on the path where
--  something raised -- a shell that exits without restoring leaves the user with
--  a terminal that does not echo, and the usual remedy is to type `reset` blind.
--
--  A Mode is opaque and is not inspected, on purpose. The host's terminal
--  settings structure differs in field width and in length between Linux and
--  macOS, and a consumer has no business knowing either; this carries the bytes
--  the host gave it and hands them back unaltered.
package Hostkit.Terminal_Control is

   --  Whether this host has a controllable terminal in the POSIX sense.
   --
   --  False on Windows for the ownership calls -- it has no process groups and
   --  therefore no foreground one -- but its console does have modes and a size,
   --  so Set_Raw, Save_Mode, Restore_Mode and Size answer there. Each operation
   --  says what it does on a host that cannot express it; this reports the
   --  ownership model specifically.
   --
   --  @return True when a foreground process group is a question this host can
   --          answer.
   function Supports_Foreground_Group return Boolean;

   --  Which process group currently owns the terminal.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @param Group The owning process group, meaningful only when this returns
   --         True.
   --  @return True when the host answered.
   function Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : out Integer) return Boolean;

   --  Give the terminal to a process group.
   --
   --  Read the note about SIGTTOU above before calling this. A shell that has
   --  not ignored Signal_Background_Write will stop itself here, and the symptom
   --  -- the shell freezing when a foreground job ends -- looks nothing like its
   --  cause.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @param Group The process group to give it to, as Hostkit.Spawn reported.
   --  @return True when the handover happened.
   function Set_Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : Integer) return Boolean;

   --  A terminal's settings, as the host records them.
   --
   --  Opaque and never interpreted: it is the host's own structure, carried
   --  from Save_Mode to Restore_Mode unchanged.
   type Mode is private;

   --  Record a terminal's current settings so they can be put back.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @param Into The settings, meaningful only when this returns True.
   --  @return True when the settings were read.
   function Save_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Mode) return Boolean;

   --  Put settings back.
   --
   --  Call it on every path out of raw mode, including the one where something
   --  raised. A terminal left raw does not echo and does not turn Ctrl-C into a
   --  signal, and the user's remedy is to type `reset` into a terminal that is
   --  not showing them what they type.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  A saved mode is not only settings. macOS keeps `PENDIN` -- a line
   --  discipline state bit -- inside the same structure, so a mode read back
   --  after a restore can differ from the one that went in while every setting
   --  was applied. Comparing two saved modes is therefore not a test of
   --  whether a restore worked, and this does not pretend otherwise: it
   --  answers what the host answered.
   --
   --  @param From Settings previously recorded by Save_Mode.
   --  @return True when the host took the settings.
   function Restore_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      From     : Mode) return Boolean;

   --  Put the terminal into raw mode: no line buffering, no echo, no signal
   --  characters, no input or output translation.
   --
   --  A read then returns as soon as one byte is available rather than waiting
   --  for a line, which is what a line editor needs and what makes Ctrl-C
   --  arrive as a byte rather than as a signal. The caller becomes responsible
   --  for everything the discipline was doing: echoing, erase and kill, and
   --  turning an interrupt character into whatever it should mean.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @return True when raw mode was set.
   function Set_Raw (Terminal : Hostkit.Descriptors.Descriptor) return Boolean;

   --  Arrange for this terminal to turn an interrupt key into an interrupt.
   --
   --  What a shell wants of its terminal *between* line reads: while a program
   --  runs, nobody is reading, and the only thing that can stop a runaway loop
   --  is the host noticing Ctrl-C by itself. On POSIX that is the line
   --  discipline's ISIG, which raw mode turns off and this turns back on. On
   --  Windows it is the console's processed input, which does the same job
   --  through a control event.
   --
   --  On Windows it also turns *off* the virtual-terminal input that raw mode
   --  turns on, and that is the half a reading of the flags does not give you:
   --  with it on the console hands Ctrl-C over as the byte three, which is
   --  right for a caller that is reading and invisible to one that is not.
   --
   --  Not the whole of cooked mode, and not the settings a caller saved: a
   --  caller that has its own mode to put back does that first and asks this
   --  afterwards, since what a saved mode carries is whatever the terminal
   --  happened to have -- a console handed over by a pseudo-console may have
   --  arrived with the flag already off.
   --
   --  @param Terminal The terminal.
   --  @return True when it will now report an interrupt key.
   function Set_Interruptible
     (Terminal : Hostkit.Descriptors.Descriptor) return Boolean;

   --  How big a terminal is, in character cells.
   type Window_Size is record
      Rows    : Natural := 0;
      Columns : Natural := 0;
   end record;

   --  Ask a terminal its size.
   --
   --  Answered by the host, not by COLUMNS and LINES in the environment: those
   --  are a shell's own convention, they are stale the moment a window is
   --  resized, and a program that inherited them from some other shell will be
   --  confidently wrong about a terminal it can measure directly.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @param Into The size, meaningful only when this returns True.
   --  @return True when the host answered. False on a descriptor that is not a
   --          terminal -- a pipe has no size, and zero is not the answer.
   function Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Window_Size) return Boolean;

   --  Tell a terminal how big it is.
   --
   --  Only meaningful for a pseudo-terminal a caller owns -- see Hostkit.Pty.
   --  Setting it is how a program running under one learns to redraw, because
   --  the host raises the window-change signal in the process group on the other
   --  side.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @param To The size to record.
   --  @return True when the size was set.
   function Set_Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      To       : Window_Size) return Boolean;

   ------------------------------------------------------------------
   --  Cursor control.
   --
   --  A line editor has to move the cursor and erase what it drew. Those are
   --  terminal control, not styling, so they belong here rather than in a
   --  styling library -- and they are expressed as actions rather than as
   --  bytes so that no caller ever holds an escape sequence. The host decides
   --  what an action costs: on POSIX these are control sequences written to
   --  the terminal, and on Windows they are the same sequences after the
   --  console has been told to interpret them.
   ------------------------------------------------------------------

   --  What to do to the cursor or the line it is on.
   type Cursor_Action is
     (
      --  Erase from the cursor to the end of the line. What a redraw does
      --  before writing a line that may be shorter than the last one.
      Erase_To_End_Of_Line,

      --  Erase the whole line the cursor is on, leaving the cursor where it
      --  was.
      Erase_Line,

      --  Move to the first column of the current line.
      To_First_Column,

      --  Move by Count cells or lines.
      Move_Left,
      Move_Right,
      Move_Up,
      Move_Down,

      --  Stop and start drawing the cursor. A redraw that leaves it visible
      --  makes it flicker across the line on every keystroke.
      Hide_Cursor,
      Show_Cursor);

   --  Whether this host can move a terminal's cursor.
   --
   --  Asked of the descriptor rather than of the host, because the answer
   --  depends on what the descriptor is: a pipe cannot be drawn on, and a
   --  Windows console that refuses virtual-terminal processing cannot either.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @return True when Control would do something.
   function Supports_Cursor_Control
     (Terminal : Hostkit.Descriptors.Descriptor) return Boolean;

   --  Perform a cursor action.
   --
   --  @param Terminal A descriptor open on the terminal.
   --  @param Action What to do.
   --  @param Count How far to move, for the movement actions; ignored by the
   --         others. Zero moves nothing and writes nothing, which is what a
   --         caller computing a distance wants when the distance is zero.
   --  @return True when the action was written in full. False when the
   --          descriptor is not a terminal this host can draw on, or when the
   --          write did not complete -- a partly written control sequence
   --          would corrupt the display, so the caller needs to know.
   function Control
     (Terminal : Hostkit.Descriptors.Descriptor;
      Action   : Cursor_Action;
      Count    : Natural := 1) return Boolean;

private

   --  Large enough for any host's terminal settings structure, with room to
   --  spare: Linux uses 60 bytes and macOS 72, and this is never indexed into,
   --  only handed back to the host. Sized generously on purpose -- a structure
   --  that grew by a field would otherwise be a buffer overrun rather than a
   --  compile error, and nothing here would notice.
   Mode_Storage_Bytes : constant := 256;

   type Mode_Storage is array (1 .. Mode_Storage_Bytes) of Interfaces.Unsigned_8;

   type Mode is record
      Bytes : Mode_Storage := [others => 0];

      --  False until Save_Mode filled it. Restoring a mode that was never saved
      --  would write zeroes over a terminal's settings, which is a far worse
      --  terminal than the raw one it was meant to undo.
      Valid : Boolean := False;
   end record;

end Hostkit.Terminal_Control;
