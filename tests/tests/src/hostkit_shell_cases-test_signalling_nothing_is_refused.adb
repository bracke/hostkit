separate (Hostkit_Shell_Cases)
procedure Test_Signalling_Nothing_Is_Refused
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
begin
   --  kill(2) reads a non-positive pid as "a group" or "everything I may
   --  signal". A caller that passed a bad id meant one process, and
   --  signalling every process it owns instead is not a near miss -- for a
   --  shell it would be every job it started, and itself.
   Assert (not Hostkit.Signals.Send_To_Process (0, Hostkit.Signals.Signal_Terminate),
           "signalling process 0 was allowed");
   Assert (not Hostkit.Signals.Send_To_Process (-1, Hostkit.Signals.Signal_Terminate),
           "signalling process -1 was allowed");
   Assert (not Hostkit.Signals.Send_To_Group (0, Hostkit.Signals.Signal_Terminate),
           "signalling group 0 was allowed");
end Test_Signalling_Nothing_Is_Refused;
