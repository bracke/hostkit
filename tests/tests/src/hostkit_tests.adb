with Ada.Command_Line;
with Ada.Text_IO;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;

with Hostkit_Suite;
with Hostkit_Test_Skips;

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

   --  A skip passes in AUnit's count, so say how many there were, and hold them
   --  against the host's list of expected skips where CI gives one.
   Ada.Text_IO.Put_Line ("Skipped Tests:" & Natural'Image (Hostkit_Test_Skips.Skip_Count));
   if not Hostkit_Test_Skips.Matches_Expected then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Hostkit_Tests;
