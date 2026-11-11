separate (Hostkit_Shell_Cases)
procedure Test_An_Unknown_Signal_Number_Is_Refused
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Decoded : Hostkit.Signals.Signal;
   --  Set by a call this test requires to refuse, so it is never read.
   pragma Warnings (Off, Decoded);
begin
   --  A signal this enumeration does not name must come back as unknown,
   --  not as whichever literal happens to be first. A job that died of
   --  SIGSEGV must not be reported as terminated by SIGTERM.
   Assert (not Hostkit.Signals.From_Number (12_345, Decoded),
           "a nonsense signal number was accepted");
end Test_An_Unknown_Signal_Number_Is_Refused;
