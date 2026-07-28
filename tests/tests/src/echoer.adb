with Ada.Command_Line;
with Ada.Text_IO;

--  Reads a line from standard input and prints what it read -- so a test can
--  tell the difference between a program that was given the file it was told
--  to read and one that was quietly handed the caller's terminal.
procedure Echoer is
begin
   declare
      Line : constant String := Ada.Text_IO.Get_Line;
   begin
      Ada.Text_IO.Put_Line ("read:" & Line);
   end;
exception
   when others =>
      --  Nothing to read at all. Distinct from an empty line, which is a line.
      Ada.Command_Line.Set_Exit_Status (3);
end Echoer;
