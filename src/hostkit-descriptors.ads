private with Interfaces;

with Ada.Streams;

--  Open files, pipes, and the ends of them a child inherits.
--
--  A shell exists to connect programs to each other and to files, which means
--  it has to talk about the connections themselves rather than about paths. A
--  pipeline is a pipe whose two ends go to different children; a redirection is
--  an opened file put where a child expects its standard output; both need the
--  parent to hold a thing it can pass, close and count.
--
--  Why this is not GNAT.OS_Lib. That package hands out an Integer it calls a
--  file descriptor, which is true on POSIX and a fiction on Windows, where the
--  kernel object is a HANDLE and the small integer is a C-runtime table index
--  belonging to whichever runtime allocated it. Passing that number to
--  CreateProcess does nothing. A Descriptor here is whatever the host actually
--  passes to a child -- an fd on POSIX, a HANDLE on Windows -- and is opaque so
--  that no consumer can assume which.
--
--  Two rules that a shell gets wrong exactly once each:
--
--  Inheritance is explicit. A descriptor is created non-inheritable and is made
--  inheritable only for the child that should get it. The failure this prevents
--  is a pipeline that hangs: the read end of a pipe left inheritable is
--  duplicated into every subsequent child, so the writer's last close never
--  makes the reader see end-of-file, and the reader waits for a program that
--  has already exited. It is not reproducible under load and it is not visible
--  in the code that caused it.
--
--  Closing is the caller's, and it matters when. The parent must close its copy
--  of each pipe end after handing it to a child; that close is what makes the
--  count reach zero. Close is idempotent and sets the descriptor invalid, so the
--  usual double-close on an error path is harmless rather than the far worse
--  thing it is on POSIX -- closing a number that some unrelated open has by then
--  reused.
package Hostkit.Descriptors is

   --  One end of something that can be read or written: an open file, a pipe
   --  end, one of this process's own standard streams, a pseudo-terminal side.
   --
   --  Opaque. On POSIX it holds a file descriptor, on Windows a HANDLE, and a
   --  consumer that needs to know which is a consumer that has already lost the
   --  portability this crate exists to provide.
   type Descriptor is private;

   --  The descriptor that is not one. Closing it is a no-op; reading or writing
   --  it fails.
   Invalid : constant Descriptor;

   --  @param Item Descriptor to test.
   --  @return True when Item refers to something.
   function Is_Valid (Item : Descriptor) return Boolean;

   --  The two ends of a pipe. Bytes written to Write_End are readable from
   --  Read_End, and Read_End reports end-of-file once every copy of Write_End
   --  is closed -- which is the whole mechanism a pipeline runs on.
   type Pipe_Ends is record
      Read_End  : Descriptor;
      Write_End : Descriptor;
   end record;

   --  Create a pipe. Both ends come back non-inheritable; make inheritable only
   --  the one end the child should receive.
   --
   --  @param Ends The two ends, valid only when this returns True.
   --  @return True when the pipe was created.
   function Create_Pipe (Ends : out Pipe_Ends) return Boolean;

   --  Close a descriptor and mark it invalid.
   --
   --  Idempotent: closing Invalid, or closing twice, does nothing. That is
   --  deliberate. On POSIX a double close is not harmless -- the number may by
   --  then belong to an unrelated open, and closing it corrupts whatever was
   --  using it, at a distance and much later. Making Close clear its argument
   --  removes the whole class.
   --
   --  @param Item Descriptor to close; Invalid afterwards.
   procedure Close (Item : in out Descriptor);

   --  Duplicate a descriptor. The copy refers to the same open file or pipe and
   --  must be closed separately. The copy is not inheritable.
   --
   --  @param Item Descriptor to duplicate.
   --  @return The copy, or Invalid on failure.
   function Duplicate (Item : Descriptor) return Descriptor;

   --  Whether a child started after this call inherits Item.
   --
   --  POSIX expresses the inverse -- FD_CLOEXEC, close on exec -- and this sets
   --  it accordingly; Windows sets the handle's inherit flag. Same question,
   --  opposite spelling, which is why it is asked here rather than by each
   --  consumer.
   --
   --  @param Item Descriptor to change.
   --  @param Inheritable True to let children inherit it.
   --  @return True when the setting was applied.
   function Set_Inheritable (Item : Descriptor; Inheritable : Boolean) return Boolean;

   --  Whether a read or write that would wait returns Would_Block instead.
   --
   --  Windows anonymous pipes have no equivalent, so this reports False there
   --  rather than pretending. A caller that needs not to block on Windows waits
   --  first -- see Hostkit.Process.Wait_FD -- which is what "ready to read"
   --  actually means on that host.
   --
   --  @param Item Descriptor to change.
   --  @param Non_Blocking True to make operations non-blocking.
   --  @return True when the setting was applied, False when the host cannot
   --          express it. False is a refusal, not a failure to be retried.
   function Set_Non_Blocking (Item : Descriptor; Non_Blocking : Boolean) return Boolean;

   --  Wait until reading would not have to wait, or a deadline passes.
   --
   --  What a caller does where Set_Non_Blocking refuses -- which is Windows,
   --  where an anonymous pipe has no non-blocking mode and a read of an empty
   --  one waits for ever. A harness driving a child through a terminal needs
   --  exactly this: read what is there, and come back rather than hang when
   --  there is nothing.
   --
   --  Ready includes *the writer having closed*. A read then returns
   --  end-of-file at once, which is not waiting; a caller that treated the two
   --  as different would loop until its deadline on a child that had already
   --  gone.
   --
   --  @param Item Descriptor to watch.
   --  @param Timeout_Ms How long to wait. Zero asks and returns; a negative
   --         value waits for as long as it takes.
   --  A console is asked a different question from a pipe, and gets a
   --  different one right: only a key going *down* with a character on it
   --  makes a read return, so releasing a key, moving a mouse and resizing a
   --  window are events that do not count. Answering from the count of events
   --  would say ready and leave the caller's read waiting.
   --
   --  @return True when a read would not wait. False on a timeout, and on a
   --          host that cannot answer -- which is a refusal, and a caller that
   --          reads anyway may block.
   function Wait_Readable
     (Item : Descriptor; Timeout_Ms : Integer) return Boolean;

   --  What became of a read.
   type Transfer_Outcome is
     ( --  Bytes were transferred; see the count.
      Transfer_Ok,

      --  The writer closed. Every copy of the write end is gone and no further
      --  bytes will arrive. A shell's reader loop ends here.
      Transfer_End_Of_File,

      --  Non-blocking, and waiting would have been required. Not an error, and
      --  not end-of-file -- confusing the two is how a pipeline loses its last
      --  buffer or spins.
      Transfer_Would_Block,

      --  Interrupted by a signal before anything was transferred. Retry.
      Transfer_Interrupted,

      --  The other end is gone and this write can never succeed. On POSIX this
      --  is EPIPE, which would otherwise raise SIGPIPE and kill the shell; the
      --  shell blocks that signal and gets this instead. `adash | head` depends
      --  on it entirely.
      Transfer_Broken_Pipe,

      Transfer_Error);

   --  Read bytes.
   --
   --  A short read is normal and is not end-of-file: a pipe returns what is in
   --  it. Only Transfer_End_Of_File means no more is coming.
   --
   --  @param Item Descriptor to read.
   --  @param Into Buffer to fill.
   --  @param Last Index of the last byte written into Into; Into'First - 1 when
   --         none.
   --  @return What became of the read.
   function Read
     (Item : Descriptor;
      Into : out Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome;

   --  Write bytes.
   --
   --  A short write is normal. The caller resumes from Last + 1; a caller that
   --  assumes the whole buffer went out loses data on a full pipe, silently.
   --
   --  @param Item Descriptor to write.
   --  @param From Bytes to write.
   --  @param Last Index of the last byte actually written; From'First - 1 when
   --         none.
   --  @return What became of the write.
   function Write
     (Item : Descriptor;
      From : Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome;

   --  This process's own standard streams, as descriptors.
   --
   --  Not closed by Close in any meaningful sense -- a shell that closes its own
   --  standard input has no way to get it back -- but usable as the source for
   --  Duplicate, which is how a shell saves a stream before redirecting it and
   --  restores it afterwards.

   --  @return This process's standard input.
   function Standard_Input return Descriptor;

   --  @return This process's standard output.
   function Standard_Output return Descriptor;

   --  @return This process's standard error.
   function Standard_Error return Descriptor;

   --  How a redirection opens a file.
   type Open_Mode is
     ( --  Existing file, read only. Fails when absent.
      Open_Read,

      --  Create or truncate, write only.
      Open_Write_Truncate,

      --  Create if absent, write only, every write at the end. Append is a
      --  property of the open file, not a seek the caller performs: two
      --  processes appending to one log must not overwrite each other, and a
      --  seek-then-write cannot promise that.
      Open_Write_Append,

      --  Create, write only, and fail if it already exists. What a shell needs
      --  to refuse to clobber a file.
      Open_Write_Exclusive,

      --  Existing file, read and write.
      Open_Read_Write);

   --  Open a file for redirection.
   --
   --  The descriptor comes back non-inheritable, like a pipe end.
   --
   --  @param Path File to open.
   --  @param Mode How to open it.
   --  @param Item The descriptor, valid only when this returns True.
   --  @return True when the file was opened.
   function Open_File
     (Path : String;
      Mode : Open_Mode;
      Item : out Descriptor) return Boolean;

   --  Whether this descriptor refers to a terminal.
   --
   --  A shell asks before deciding to prompt, to style, or to take the terminal
   --  for a foreground job.
   --
   --  @param Item Descriptor to test.
   --  @return True when Item is a terminal.
   function Is_Terminal (Item : Descriptor) return Boolean;

   --  Return the host pathname or conventional name for a terminal descriptor.
   --
   --  POSIX hosts use ttyname-style answers where available. Windows consoles
   --  do not have POSIX device pathnames, so a stable conventional console name
   --  is returned when the descriptor is a console. Empty means Item is not a
   --  terminal or the host cannot provide a name.
   --
   --  @param Item Descriptor to name.
   --  @return Terminal name, or the empty string.
   function Terminal_Name (Item : Descriptor) return String;

   --  Which of the three standard streams a descriptor is to become.
   type Standard_Stream is (Stream_Input, Stream_Output, Stream_Error);

   --  Put Item where one of the standard streams is looked for.
   --
   --  Two callers, and the second was using it on the first's documentation.
   --
   --  A child, between fork and exec: this is here rather than in
   --  Hostkit.Spawn so that the knowledge of how a host attaches a stream --
   --  dup2 and the close-on-exec flag it clears on POSIX, SetStdHandle and the
   --  STARTUPINFO fields on Windows -- stays with the descriptors, and so that
   --  Hostkit.Spawn never needs to see the host value behind one.
   --
   --  This process, to redirect a stream and put it back. Save the stream
   --  first with Duplicate, assign the new descriptor, and assign the saved
   --  one when finished; the redirection is a property of the process, so
   --  anything written through a language runtime's own standard-output
   --  object follows it, which is the point -- that object cannot be
   --  redirected from inside the language when the writer holds the raw
   --  stream. One at a time: the state being changed is process-wide, so a
   --  second redirection taken before the first is put back loses the
   --  descriptor that would have restored it.
   --
   --  The assignment survives exec: whatever this package's usual
   --  non-inheritable default was, the assigned stream is inherited, because a
   --  child with no standard output is not what any caller meant. In-process
   --  that costs nothing -- a standard stream is inheritable already -- and it
   --  is stated because it is a change to process state either way.
   --
   --  @param Item Descriptor to install.
   --  @param To Which stream it becomes.
   --  @return True when the assignment was made.
   --  On Windows this changes the process's standard handles -- what a child
   --  and any later reader of them find -- and does not move where this
   --  program's *own* writes go: a runtime that opened its output once goes on
   --  writing where it did. POSIX has no such split, because dup2 moves the
   --  descriptor every writer already holds. A caller redirecting itself has
   --  to know which of the two it is getting; adash's `redirect` refuses on
   --  Windows for this reason.
   function Assign (Item : Descriptor; To : Standard_Stream) return Boolean;

   --  The host's own value behind a descriptor.
   --
   --  For the other Hostkit packages that must hand a descriptor to a host call
   --  this package does not wrap: Hostkit.Terminal_Control and Hostkit.Pty.
   --
   --  Consumers outside this crate must not use it. The value is a file
   --  descriptor on POSIX and a HANDLE on Windows, and a consumer that reads it
   --  has to know which -- which is exactly the portability the opaque type
   --  exists to provide, given up.
   --
   --  @param Item Descriptor to unwrap.
   --  @return The host's value, or -1 for Invalid.
   function Native_Value (Item : Descriptor) return Long_Long_Integer;

   --  Wrap a host value this crate obtained from a call it does not otherwise
   --  wrap -- the two sides of a pseudo-terminal, for instance.
   --
   --  Same restriction as Native_Value: inside this crate only.
   --
   --  @param Value The host's value.
   --  @return The descriptor, or Invalid when Value is negative.
   function From_Native_Value (Value : Long_Long_Integer) return Descriptor;

private

   --  Wide enough for a Windows HANDLE, which is pointer-sized, as well as a
   --  POSIX descriptor. One representation for both hosts keeps the type
   --  opaque; a consumer never learns which it is holding.
   type Descriptor is new Interfaces.Integer_64;

   Invalid : constant Descriptor := -1;

end Hostkit.Descriptors;
