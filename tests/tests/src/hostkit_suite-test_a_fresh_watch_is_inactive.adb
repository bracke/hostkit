separate (Hostkit_Suite)
procedure Test_A_Fresh_Watch_Is_Inactive (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   State : Hostkit.Watch.Watch_State;
begin
   Assert (not Hostkit.Watch.Is_Active (State), "a fresh watch is inactive");
   Assert (not Hostkit.Watch.Poll (State), "polling an inactive watch reports no change");
end Test_A_Fresh_Watch_Is_Inactive;
