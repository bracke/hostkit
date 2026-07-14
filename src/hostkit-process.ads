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
