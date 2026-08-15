with Hostkit.Descriptors;
with Hostkit.Spawn;
with Hostkit.Terminal_Control;

--  Pseudo-terminals: a terminal that is a program rather than a device.
--
--  A pipe is not a terminal, and programs can tell. They line-buffer their
--  output down a pipe and flush it per line to a terminal; they colour for one
--  and not the other; some refuse outright to prompt for a password unless they
--  have a terminal to prompt on. Anything that has to run another program *as
--  if a user were watching* -- a shell recording a session, a test harness
--  driving an interactive tool, a terminal emulator -- needs a pseudo-terminal
--  rather than a pipe.
--
--  A pair has two sides and they are not symmetric. The parent keeps the
--  controlling side: bytes written to it appear as keystrokes to the child, and
--  bytes the child writes come back out of it. The child gets the other side,
--  which behaves in every respect like a real terminal -- it has a line
--  discipline, a window size, and a foreground process group that receives
--  Ctrl-C.
--
--  **The two hosts hand the child its side differently, and Attach is the
--  difference.** Where there are pseudo-terminals the child's side is a
--  descriptor, handed over as its three standard streams. Windows has the
--  pseudo-console instead: a pair of ordinary pipes and an HPCON, which reaches
--  a child through a process-thread attribute rather than as anything it
--  inherits, and there is no device to name or to open. A caller that fills in
--  Options itself would therefore be writing two different programs; Attach
--  fills them in for the host it is on.
--
--  For the same reason the parent's side is *two* descriptors here. A
--  pseudo-terminal is one bidirectional descriptor and both fields hold it; a
--  pseudo-console is two pipes and they differ. Code that writes to To_Child
--  and reads From_Child is right on both.
--
--  Two things a caller must do that are easy to leave out:
--
--  Close the device side in the parent once the child has it. As with a pipe,
--  the count is what matters: while the parent still holds the device open, the
--  controller never reports end-of-file, and a reader waits for a child that
--  exited long ago.
--
--  Set the size. A fresh pseudo-terminal reports zero rows and zero columns,
--  and a program that asks will either use a hard-coded fallback or produce
--  nothing at all. Hostkit.Terminal_Control.Set_Size on the controller is the
--  call, and repeating it when the real window changes is what makes a program
--  under the pseudo-terminal redraw -- the host raises the window-change signal
--  on the other side.
package Hostkit.Pty is

   --  Whether this host can give a child a terminal.
   --
   --  True on all three hosts now. Windows answers with the pseudo-console,
   --  which is a different shape of API rather than this one under another
   --  name -- see Attach, and see that Device_Name has nothing to say there.
   --  It needs Windows 10 1809 or later, which is where CreatePseudoConsole
   --  first appears; on an older one this is False and Open refuses rather
   --  than a consumer discovering it from a call that did not link.
   --
   --  @return True when Open can succeed on this host.
   function Is_Supported return Boolean;

   --  The two sides of a pseudo-terminal.
   type Pair is record
      --  The parent's side, for writing keystrokes to the child.
      To_Child : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;

      --  The parent's side, for reading what the child produced. The same
      --  descriptor as To_Child where a pseudo-terminal is one bidirectional
      --  thing, and the other end of a second pipe where it is not.
      From_Child : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;

      --  The child's side, where the host has one to hand over. Attach gives it
      --  to a child as its three standard streams; close this copy afterwards.
      --  Invalid on a host whose answer is a console rather than a device.
      Device : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;

      --  The child's side, where the host's answer is a console. Attach passes
      --  it on; nothing else here reads it. No_Console where there is a device
      --  instead.
      Console : Hostkit.Spawn.Console_Attachment := Hostkit.Spawn.No_Console;
   end record;

   --  Arrange for a child to be started on this terminal.
   --
   --  The one call that knows how this host gives a terminal to a child: the
   --  device side as three standard streams and a controlling terminal where
   --  there are sessions, the console where there is a console. A caller that
   --  set Options.Input and the rest by hand would have written the POSIX half
   --  of that and nothing else.
   --
   --  It also marks the child's side inheritable where there is one to mark,
   --  because a caller doing that by hand is a caller writing the POSIX half
   --  again. What it does not do is close the parent's copy of that side --
   --  Close_Device is that, after the child has started.
   --
   --  @param Item The pair to run the child on.
   --  @param To Options to fill in, otherwise untouched.
   --  @return False when the host would not hand the child's side over, which
   --          leaves To unfit to start with.
   function Attach (Item : Pair; To : in out Hostkit.Spawn.Options)
                    return Boolean;

   --  Give up the parent's copy of the child's side, once the child has it.
   --
   --  As with a pipe, the count of copies is what matters: while the parent
   --  still holds the child's side open, reading the parent's side never
   --  reports end-of-file and a harness waits for a child that exited long
   --  ago. Nothing to do on a host whose answer is a console -- there is no
   --  second copy there -- and calling it anyway is how a caller stays one
   --  program.
   --
   --  @param Item The pair, whose Device is Invalid afterwards.
   procedure Close_Device (Item : in out Pair);

   --  Make a pseudo-terminal.
   --
   --  Both sides come back non-inheritable, like every other descriptor this
   --  crate hands out; mark the device side inheritable for the one child that
   --  should receive it.
   --
   --  @param Item The pair, valid only when this returns True.
   --  @return True when the host made one.
   function Open (Item : out Pair) return Boolean;

   --  The device side's name in the filesystem, for a child that must open it
   --  by name to make it its controlling terminal.
   --
   --  Inheriting the descriptor is enough for most programs. A child that calls
   --  setsid, and so leaves the controlling terminal behind, needs the name to
   --  get a new one.
   --
   --  "" where the host's terminal is a console: a pseudo-console has no path,
   --  and a plausible-looking "CONOUT$" would name something else entirely.
   --
   --  @param Item Pair to name.
   --  @return The device path, or "" when the host cannot say.
   function Device_Name (Item : Pair) return String;

   --  Close both sides.
   --
   --  @param Item Pair to close; both sides Invalid afterwards.
   procedure Close (Item : in out Pair);

   --  Set the size of a fresh pseudo-terminal.
   --
   --  A convenience over Hostkit.Terminal_Control.Set_Size on the controller,
   --  here because a pair that is never sized is the single most common way to
   --  get this wrong: the child sees zero by zero and lays out for a terminal
   --  that has no room in it.
   --
   --  @param Item Pair to size.
   --  @param To The size to record.
   --  @return True when the size was set.
   function Set_Size
     (Item : Pair;
      To   : Hostkit.Terminal_Control.Window_Size) return Boolean;

end Hostkit.Pty;
