with Ada.Command_Line;

procedure Failing is
begin
   --  A program that fails, for tests that check a non-zero exit is reported.
   Ada.Command_Line.Set_Exit_Status (7);
end Failing;
