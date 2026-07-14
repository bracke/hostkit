with Hostkit.Process;

package body Hostkit.Native is

   --  An unknown host: nothing is claimed, and nothing is pretended.
   procedure Reap_Finished_Children is
   begin
      null;
   end Reap_Finished_Children;

   function Supports_Raw_Command_Line return Boolean is
   begin
      return False;
   end Supports_Raw_Command_Line;

   function Run_Command_Line
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean
   is
      pragma Unreferenced (Command, Wait);
   begin
      Exit_Status := -1;
      return False;
   end Run_Command_Line;

   function Run_Captured
     (Program           : String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : String;
      Stdout_Path       : String;
      Stderr_Path       : String;
      Timeout_Ms        : Natural;
      Cancelled         : Hostkit.Process.Cancel_Check;
      Poll              : Hostkit.Process.Poll_Hook)
      return Hostkit.Process.Process_Outcome
   is
      pragma Unreferenced
        (Program, Arguments, Working_Directory, Stdout_Path, Stderr_Path,
         Timeout_Ms, Cancelled, Poll);
      Nothing : Hostkit.Process.Process_Outcome;
   begin
      return Nothing;
   end Run_Captured;

   function Open_Native (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Open_Native;

end Hostkit.Native;
