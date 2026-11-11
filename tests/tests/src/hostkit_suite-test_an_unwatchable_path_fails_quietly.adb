separate (Hostkit_Suite)
procedure Test_An_Unwatchable_Path_Fails_Quietly (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   State : Hostkit.Watch.Watch_State;
begin
   --  A watch that cannot be established leaves the caller to its polling
   --  timer rather than raising: the listing still refreshes, less promptly.
   Hostkit.Watch.Watch_Path (State, Ada.Directories.Compose (Scratch, "no-such-directory-xyzzy"));
   Assert (not Hostkit.Watch.Is_Active (State), "an unwatchable path does not activate");
   Assert (not Hostkit.Watch.Poll (State), "a watch that failed simply reports no change");

   Hostkit.Watch.Watch_Path (State, "");
   Assert (not Hostkit.Watch.Is_Active (State), "an empty path does not activate");
end Test_An_Unwatchable_Path_Fails_Quietly;
