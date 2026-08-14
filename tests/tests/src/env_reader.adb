with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Text_IO;

--  Prints what one environment variable holds, named by the first argument.
--
--  For the question a spawn test cannot otherwise ask: a child given a
--  replaced environment has to be able to say what it was given, and only the
--  child can see it. Exits 4 when the variable is not there at all, which is a
--  different answer from an empty one.
procedure Env_Reader is
begin
   if Ada.Command_Line.Argument_Count < 1 then
      Ada.Command_Line.Set_Exit_Status (5);
      return;
   end if;

   declare
      Named : constant String := Ada.Command_Line.Argument (1);
   begin
      if not Ada.Environment_Variables.Exists (Named) then
         Ada.Text_IO.Put_Line ("absent");
         Ada.Command_Line.Set_Exit_Status (4);
         return;
      end if;

      Ada.Text_IO.Put_Line ("value:" & Ada.Environment_Variables.Value (Named));
   end;
end Env_Reader;
