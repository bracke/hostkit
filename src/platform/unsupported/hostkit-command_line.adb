with Ada.Command_Line;

package body Hostkit.Command_Line is

   --  Nothing is known about this host, so the runtime's own answer is the
   --  only one available: there is no command line to ask the system for.

   function Argument_Count return Natural is
   begin
      return Ada.Command_Line.Argument_Count;
   end Argument_Count;

   function Argument (Index : Positive) return String is
   begin
      return Ada.Command_Line.Argument (Index);
   end Argument;

end Hostkit.Command_Line;
