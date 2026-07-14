--  The parts of starting a program that only the host can answer. One body per OS;
--  everything above this is portable and shared.
with Hostkit.Process;

private package Hostkit.Native is

   --  Collect any children that have already finished, and return at once whether or
   --  not there are any. It must never wait for one that is still running -- see the
   --  note on exiting in Hostkit.Process.
   --
   --  A no-op on Windows, which leaves nothing behind to collect.
   procedure Reap_Finished_Children;

   --  Can this host run a *raw* command line -- the exact string a shell parses --
   --  rather than an argument vector?
   --
   --  True only on Windows, and only because there it is the sole way to get a command
   --  line to cmd intact: the C runtime rebuilds a command line from the vector,
   --  re-quoting each argument and escaping the quotes we put there, and cmd then
   --  strips the first and last quote it finds. The line is mangled twice before cmd
   --  ever parses it, and no quoting on our side survives the round trip.
   function Supports_Raw_Command_Line return Boolean;

   --  Run Command verbatim as a process command line. Only meaningful where
   --  Supports_Raw_Command_Line.
   function Run_Command_Line
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean;

   --  Run a program to completion with its output captured, under a deadline. See
   --  Hostkit.Process.Run_Captured, which is the documented face of this.
   function Run_Captured
     (Program           : String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : String;
      Stdout_Path       : String;
      Stderr_Path       : String;
      Timeout_Ms        : Natural;
      Cancelled         : Hostkit.Process.Cancel_Check)
      return Hostkit.Process.Process_Outcome;

   --  Start whatever the host thinks Path is, the way a double-click would.
   function Open_Native (Path : String) return Boolean;

end Hostkit.Native;
