separate (Hostkit_Shell_Cases)
procedure Test_Can_Record_Agrees_With_Set_Disposition
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
begin
   --  Can_Record is a promise, and this is the test that it is kept. A
   --  caller decides whether to offer Ctrl-C on the strength of it, so a
   --  host answering yes and then refusing the disposition would send that
   --  caller down a path with no way back.
   --
   --  Both directions matter. Answering yes and refusing strands the
   --  caller; answering no and succeeding hides a capability the host has,
   --  which is how a platform ends up permanently poorer than it needs to
   --  be because nobody rechecked.
   for Item in Hostkit.Signals.Signal loop
      declare
         Claimed : constant Boolean := Hostkit.Signals.Can_Record (Item);
         Actual  : constant Boolean :=
           Hostkit.Signals.Set_Disposition (Item, Hostkit.Signals.Disposition_Record);
      begin
         Assert (Claimed = Actual,
                 "Can_Record and Set_Disposition disagree about "
                 & Hostkit.Signals.Name (Item)
                 & ": claimed " & Boolean'Image (Claimed)
                 & ", got " & Boolean'Image (Actual));

         --  Put it back before the next case. Left installed, a recorder on
         --  SIGPIPE or SIGCHLD would change how every later test in this
         --  suite behaves, and the failure would land somewhere else.
         if Actual then
            declare
               Restored : constant Boolean :=
                 Hostkit.Signals.Set_Disposition
                   (Item, Hostkit.Signals.Disposition_Default);
            begin
               Assert (Restored,
                       "a signal that accepted a recorder would not go back "
                       & "to its default: " & Hostkit.Signals.Name (Item));
            end;
            Hostkit.Signals.Clear (Item);
         end if;
      end;
   end loop;

   --  The two signals POSIX will not let anyone catch. Named rather than
   --  left to the loop above, because "no host claims these" is the part
   --  that would be wrong to quietly start claiming.
   Assert (not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Kill),
           "a host claimed it could record KILL");
   Assert (not Hostkit.Signals.Can_Record (Hostkit.Signals.Signal_Stop),
           "a host claimed it could record STOP");
end Test_Can_Record_Agrees_With_Set_Disposition;
