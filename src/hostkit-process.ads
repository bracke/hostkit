--  Starting other programs.
--
--  Two constraints shaped all of this, and both are easy to get wrong:
--
--  A detached launch must not be done by asking a shell to background the process --
--  "( ... & )", "start "" /b". That is what it used to mean, purely because the spawn
--  underneath blocks and something had to make it return. It bought a cross-platform
--  quoting problem in the path of every launch, it hung on Windows, and the exit
--  status it reported was the wrapper shell's: the shell exited zero having
--  successfully backgrounded a program that then went on to fail.
--
--  And nothing here may *wait* on a launched program in a task. An Ada environment
--  task waits for library-level tasks to finish, so a task parked on a child would
--  stop the application from exiting: quit the file manager while the editor you
--  opened is still running, and it would hang on quit. The reaper below collects only
--  children that have *already* finished, and can never hold up exit.
package Hostkit.Process is

   --  Start Program with these arguments and return at once.
   --
   --  Fire-and-forget: there is no exit status, and the caller is told only whether
   --  the launch began. A program a user opens something in may run for hours, so
   --  there is nothing to wait for and none is offered.
   --
   --  Arguments go to the operating system as a vector, so a filename containing a
   --  space, a quote or a semicolon is just a filename.
   function Launch
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean;

   --  Run Program to completion and report its exit status. For a short-lived helper,
   --  where the status is the point.
   function Run
     (Program     : String;
      Arguments   : String_Vectors.Vector;
      Exit_Status : out Integer)
      return Boolean;

   --  Run Command through the host's shell -- see Hostkit.Shell for what that means
   --  and how it is quoted.
   --
   --  @param Command The command line, already quoted as the shell expects.
   --  @param Wait True to run it to completion, False to start it and return.
   --  @param Exit_Status The exit status when Wait, else -1.
   function Run_Shell_Command
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean;

   --  Ask a process we are not waiting on to stop -- one whose id we were given, rather
   --  than one we are inside Run_Captured for. A user cancelling a build needs this.
   --
   --  POSIX sends SIGTERM. Windows has no signal to send: it opens the process and
   --  terminates it, which is the only way to say it there.
   --
   --  @return True when the request reached the process.
   function Request_Stop (Process_Id : Integer) return Boolean;

   --  Which process-control body is compiled in. Hostkit is the one thing that knows,
   --  because it is the one thing with a body per host.
   function Native_Backend_Label return String;

   --  What became of a process we ran and waited for.
   type Process_Outcome is record
      Started     : Boolean := False;
      Timed_Out   : Boolean := False;
      Exit_Status : Integer := -1;
   end record;

   --  Asked periodically while waiting. Returning True kills the process, the same way a
   --  timeout does. Null means nothing can cancel it.
   type Cancel_Check is access function return Boolean;

   --  Called periodically while waiting, so a caller can do something with the output as
   --  it arrives rather than only once the program has finished. A build that streams its
   --  progress needs this; without it the output appears all at once, at the end.
   type Poll_Hook is access procedure;

   --  Called once, with the operating system's process id, as soon as the program starts.
   --  A caller that shows or tracks a running job needs the id to talk about it.
   type Started_Hook is access procedure (Process_Id : Integer);

   --  Run a program to completion, with its output captured to files, under a deadline.
   --
   --  This is what a tool runner needs and Run does not give it: somewhere for the
   --  output to go, a directory to run in, and a way to stop waiting. A compiler invoked
   --  on a bad day does not return, and a caller that cannot give up on it is stuck.
   --
   --  On a deadline or a cancellation the process is asked to stop and then made to: on
   --  POSIX, SIGTERM and then SIGKILL; on Windows, TerminateProcess.
   --
   --  @param Program The program to run; looked up on PATH if it is not a path.
   --  @param Arguments Its arguments, as a vector -- never a command line, so a filename
   --                   containing a space or a quote is just a filename.
   --  @param Working_Directory Where to run it; the current directory when empty.
   --  @param Stdout_Path File to capture standard output into; discarded when empty.
   --  @param Stderr_Path File to capture standard error into; discarded when empty.
   --  @param Timeout_Ms How long to wait before killing it; 0 waits indefinitely.
   --  @param Cancelled Asked while waiting; True kills the process.
   --  @return What became of it. Timed_Out says the deadline (or a cancellation) ended it,
   --          rather than the program deciding to stop.
   function Run_Captured
     (Program           : String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : String := "";
      Stdout_Path       : String := "";
      Stderr_Path       : String := "";
      Timeout_Ms        : Natural := 0;
      Cancelled         : Cancel_Check := null;
      Poll              : Poll_Hook := null;
      Started           : Started_Hook := null)
      return Process_Outcome;

   --  Start whatever the host thinks this path is: a document in its default
   --  application, a Start Menu shortcut, an application bundle.
   --
   --  This is not "run a program". It is what a double-click does, and it is the only
   --  way in on Windows for a thing whose path contains spaces: a quoted command line
   --  cannot be got to cmd through an argument vector, because the C runtime escapes
   --  the quotes on the way and cmd then strips the ones it finds. ShellExecuteW takes
   --  the path itself, and nothing quotes or parses anything.
   function Open_Native (Path : String) return Boolean;

end Hostkit.Process;
