with Ada.Calendar;
with Ada.Command_Line;
with Ada.Text_IO;

with Hostkit.Descriptors;
with Hostkit.Signals;
with Hostkit.Terminal_Control;

--  Spins on a terminal that was asked to report an interrupt, and says whether
--  it was ever told.
--
--  The companion for one claim this crate makes and could not otherwise check:
--  Interrupt_Reaches_A_Busy_Program. A program that is *waiting* is told about
--  Ctrl-C on every host, which is why the answer cannot be measured by waiting
--  for it -- what separates the hosts is what happens to a program that is
--  busy, and being busy is the whole of what this does.
--
--  It writes into a file it is told to open, for the same reason the terminal
--  reporter does: a program asked what it saw on its own terminal cannot
--  answer on that terminal if the answer is that it saw nothing.
--
--  What it records:
--
--    * `armed=` whether the interrupt disposition took, since a False here
--      makes everything below meaningless rather than negative,
--    * `interruptible=` whether the terminal took the setting,
--    * `told=` whether the interrupt arrived while it spun,
--    * `after=` the same question half a second after it stopped spinning,
--      which tells a late notice apart from one that never came.
procedure Busy_Watcher is
   Where : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1) else "");

   Seconds : constant Duration :=
     (if Ada.Command_Line.Argument_Count >= 2
      then Duration'Value (Ada.Command_Line.Argument (2)) else 4.0);

   Report : Ada.Text_IO.File_Type;

   Told    : Boolean := False;
   Started : Ada.Calendar.Time;

   use type Ada.Calendar.Time;
begin
   if Where = "" then
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Ada.Text_IO.Create (Report, Ada.Text_IO.Out_File, Where);

   Ada.Text_IO.Put_Line
     (Report,
      "armed="
      & Boolean'Image
          (Hostkit.Signals.Set_Disposition
             (Hostkit.Signals.Signal_Interrupt,
              Hostkit.Signals.Disposition_Record)));

   Ada.Text_IO.Put_Line
     (Report,
      "interruptible="
      & Boolean'Image
          (Hostkit.Terminal_Control.Set_Interruptible
             (Hostkit.Descriptors.Standard_Input)));

   Ada.Text_IO.Flush (Report);

   Started := Ada.Calendar.Clock;

   --  Bounded by the clock rather than by a count of turns: ten million asks
   --  take a fraction of a second, and a loop that ended before anything had
   --  been typed would measure nothing at all. What is wanted is a program
   --  that is busy *while the keystroke arrives*.
   while not Told and then Ada.Calendar.Clock - Started < Seconds loop
      for Turn in 1 .. 100_000 loop
         Told := Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Interrupt);
         exit when Told;
      end loop;
   end loop;

   Ada.Text_IO.Put_Line (Report, "told=" & Boolean'Image (Told));
   Ada.Text_IO.Flush (Report);

   --  Asked once more with nothing to do. A host that delivers the notice on a
   --  thread of its own might simply have needed a moment, and "late" and
   --  "never" are two different facts about a host.
   delay 0.5;

   Ada.Text_IO.Put_Line
     (Report,
      "after="
      & Boolean'Image
          (Hostkit.Signals.Arrived (Hostkit.Signals.Signal_Interrupt)));

   Ada.Text_IO.Put_Line (Report, "end");
   Ada.Text_IO.Close (Report);
end Busy_Watcher;
