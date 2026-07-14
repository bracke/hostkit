with AUnit.Reporter.Text;
with AUnit.Run;

with Hostkit_Suite;

procedure Hostkit_Tests is
   procedure Run is new AUnit.Run.Test_Runner (Hostkit_Suite.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   Run (Reporter);
end Hostkit_Tests;
