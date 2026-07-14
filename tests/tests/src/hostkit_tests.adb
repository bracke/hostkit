with Ada.Command_Line;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;

with Hostkit_Suite;

--  Test_Runner exits zero whatever happens, so a failing suite reported success and CI
--  went green over it. The status is the whole point of running this in CI.
procedure Hostkit_Tests is
   use type AUnit.Status;

   function Run is new AUnit.Run.Test_Runner_With_Status (Hostkit_Suite.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   if Run (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Hostkit_Tests;
