with Ada.Command_Line;

package body Hostkit.Command_Line is

   --  The kernel hands execve's argument vector straight to the program and
   --  nothing between the shell and main() rewrites it, so what the runtime
   --  reports is what was passed.

   function Argument_Count return Natural is
   begin
      return Ada.Command_Line.Argument_Count;
   end Argument_Count;

   function Argument (Index : Positive) return String is
   begin
      return Ada.Command_Line.Argument (Index);
   end Argument;

end Hostkit.Command_Line;
