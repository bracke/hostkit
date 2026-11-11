separate (Hostkit_Shell_Cases)
procedure Test_Kill_And_Stop_Cannot_Be_Caught
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
begin
   --  POSIX forbids it, and this must refuse rather than appear to succeed:
   --  a shell that believed it had ignored SIGKILL would be relying on
   --  something that cannot happen.
   Assert (not Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Kill, Hostkit.Signals.Disposition_Ignore),
           "ignoring SIGKILL reported success");
   Assert (not Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Stop, Hostkit.Signals.Disposition_Ignore),
           "ignoring SIGSTOP reported success");
end Test_Kill_And_Stop_Cannot_Be_Caught;
