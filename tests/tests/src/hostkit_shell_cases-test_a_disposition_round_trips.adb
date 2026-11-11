separate (Hostkit_Shell_Cases)
procedure Test_A_Disposition_Round_Trips
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Current : Hostkit.Signals.Disposition;
begin
   if not Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Pipe) then
      Skip ("Test_A_Disposition_Round_Trips", "this host has no SIGPIPE");
      return;
   end if;

   --  SIGPIPE, because it is the one a shell must ignore or die on its
   --  first truncated pipeline.
   Assert (Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Pipe, Hostkit.Signals.Disposition_Ignore),
           "could not ignore SIGPIPE");
   Assert (Hostkit.Signals.Current_Disposition
             (Hostkit.Signals.Signal_Pipe, Current),
           "could not read back the SIGPIPE disposition");
   Assert (Current = Hostkit.Signals.Disposition_Ignore,
           "SIGPIPE did not stay ignored");

   Assert (Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Pipe, Hostkit.Signals.Disposition_Default),
           "could not restore SIGPIPE");
   Assert (Hostkit.Signals.Current_Disposition
             (Hostkit.Signals.Signal_Pipe, Current),
           "could not read back the restored SIGPIPE disposition");
   Assert (Current = Hostkit.Signals.Disposition_Default,
           "SIGPIPE did not go back to the default");
end Test_A_Disposition_Round_Trips;
