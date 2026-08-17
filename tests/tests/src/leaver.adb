with Ada.Command_Line;
with Ada.Text_IO;

with Hostkit.Process;

--  Ends through Hostkit.Process.End_Now with the status it was told.
--
--  A companion, because the thing under test is a procedure that does not
--  return: a case cannot call it and go on to assert anything, and a process
--  that has stopped is the only witness to a stop.
--
--  It writes a line first. That line is not what the case asserts -- whether a
--  buffer survives a way out that runs no finalizer is the host's business and
--  differs -- but a program that wrote nothing at all could have died before
--  reaching the call, and this way the record says which.
procedure Leaver is
   Status : constant Integer :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Integer'Value (Ada.Command_Line.Argument (1)) else 0);
begin
   Ada.Text_IO.Put_Line ("leaving");
   Ada.Text_IO.Flush;

   Hostkit.Process.End_Now (Status);
end Leaver;
