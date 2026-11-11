separate (Hostkit_Shell_Cases)
procedure Test_A_Recorded_Signal_Is_Remembered
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
begin
   if not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Window_Change) then
      --  A host that cannot record this signal says so rather than
      --  appearing to. Can_Record rather than Is_Supported: recording is
      --  the narrower capability, and this test is about recording.
      Assert (not Hostkit.Signals.Set_Disposition
                (Hostkit.Signals.Signal_Window_Change,
                 Hostkit.Signals.Disposition_Record),
              "a host without the signal accepted a disposition for it");
      return;
   end if;

   --  Window_Change rather than Interrupt: a test that arranged to be
   --  interrupted would be one that kills the suite if the disposition does
   --  not take, and this one is harmless whatever happens to it.
   Assert (Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Window_Change,
              Hostkit.Signals.Disposition_Record),
           "the recording disposition was refused");

   --  Nothing yet: installing clears, so a signal that arrived before
   --  anybody was listening is not reported to whoever just started.
   Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
           "a freshly installed recorder already reported an arrival");

   Assert (Hostkit.Signals.Send_To_Process
             (Hostkit.Host.Own_Process_Id, Hostkit.Signals.Signal_Window_Change),
           "the signal could not be sent to this process");

   --  The handler runs between two instructions of this program, so by the
   --  time the send has returned the flag is set. This is the whole
   --  mechanism: a handler may do almost nothing, so it records and the
   --  program asks at a moment of its own choosing.
   Assert (Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
           "a signal that was sent was not recorded");

   --  And it stays recorded until acknowledged: a program that asks twice
   --  must get the same answer, or whether it stops depends on how often
   --  it happened to look.
   Assert (Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
           "asking twice consumed the arrival");

   Hostkit.Signals.Clear (Hostkit.Signals.Signal_Window_Change);
   Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Window_Change),
           "clearing did not forget the arrival");

   --  A signal nobody recorded never arrives, whatever happens to it.
   Assert (not Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Terminate),
           "a signal with no recorder reported an arrival");

   declare
      Ignored : constant Boolean :=
        Hostkit.Signals.Set_Disposition
          (Hostkit.Signals.Signal_Window_Change,
           Hostkit.Signals.Disposition_Default);
   begin
      Assert (Ignored or else not Ignored, "unreachable");
   end;
end Test_A_Recorded_Signal_Is_Remembered;
