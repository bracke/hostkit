separate (Hostkit_Shell_Cases)
procedure Test_A_Taken_Signal_Is_Gone_And_A_Replaced_Disposition_Is_Said
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Was : Hostkit.Signals.Disposition;
begin
   if not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Window_Change) then
      Skip ("Test_A_Taken_Signal_Is_Gone_And_A_Replaced_Disposition_Is_Said", "this host records no window changes");
      return;
   end if;

   --  Ignored first: what is replaced is said, so a program that takes a
   --  signal for a while can give back what it took over -- the ignored
   --  SIGHUP of a job under nohup.
   Assert (Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Window_Change, Hostkit.Signals.Disposition_Ignore),
           "the window change could not be ignored");
   Assert (Hostkit.Signals.Replace_Disposition
             (Hostkit.Signals.Signal_Window_Change, Hostkit.Signals.Disposition_Record, Was),
           "the recorder could not replace the ignoring");
   Assert (Was = Hostkit.Signals.Disposition_Ignore,
           "the ignoring replaced was said to be " & Hostkit.Signals.Disposition'Image (Was));

   --  Taken once, gone: the second take sees nothing.
   Assert (not Hostkit.Signals.Take (Hostkit.Signals.Signal_Window_Change),
           "a fresh recorder had something to take");
   Assert (Hostkit.Signals.Send_To_Process
             (Hostkit.Host.Own_Process_Id, Hostkit.Signals.Signal_Window_Change),
           "the signal could not be sent to this process");
   Assert (Hostkit.Signals.Take (Hostkit.Signals.Signal_Window_Change),
           "a signal that was sent was not taken");
   Assert (not Hostkit.Signals.Take (Hostkit.Signals.Signal_Window_Change),
           "a taken signal was taken again");
   Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
           "a taken signal was still said to have arrived");

   --  And the recorder itself is said when it is replaced.
   Assert (Hostkit.Signals.Replace_Disposition
             (Hostkit.Signals.Signal_Window_Change, Hostkit.Signals.Disposition_Default, Was),
           "the default could not replace the recorder");
   Assert (Was = Hostkit.Signals.Disposition_Record,
           "the recorder replaced was said to be " & Hostkit.Signals.Disposition'Image (Was));
end Test_A_Taken_Signal_Is_Gone_And_A_Replaced_Disposition_Is_Said;
