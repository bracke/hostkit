with Hostkit.Descriptors;
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
--  A pair has two sides and they are not symmetric. The controller is the side
--  the parent keeps: bytes written to it appear as keystrokes to the child, and
--  bytes the child writes come back out of it. The device is the side the child
--  gets as its standard streams, and it behaves in every respect like a real
--  terminal -- it has a line discipline, a window size, and a foreground process
--  group that receives Ctrl-C.
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

   --  Whether this host can make a pseudo-terminal.
   --
   --  False on Windows. Its answer is the pseudo-console -- CreatePseudoConsole
   --  and a pair of ordinary pipes -- which is a different shape of API rather
   --  than the same one under another name, and is not implemented here. A
   --  consumer degrades explicitly on that host rather than discovering it from
   --  a failed Open.
   --
   --  @return True when Open can succeed on this host.
   function Is_Supported return Boolean;

   --  The two sides of a pseudo-terminal.
   type Pair is record
      --  The parent's side. Write to it to send keystrokes, read from it to
      --  collect what the child produced.
      Controller : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;

      --  The child's side. Hand it to Hostkit.Spawn as all three standard
      --  streams, then close this copy.
      Device : Hostkit.Descriptors.Descriptor := Hostkit.Descriptors.Invalid;
   end record;

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
