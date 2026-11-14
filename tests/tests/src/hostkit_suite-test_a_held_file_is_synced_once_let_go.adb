with Ada.Real_Time;

with Hostkit_Test_Native;

separate (Hostkit_Suite)
procedure Test_A_Held_File_Is_Synced_Once_Let_Go
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;
   use type Hostkit.Durability.Outcome;
   Path    : constant String := Ada.Directories.Compose (Scratch, "hostkit-held-sync");
   Held    : Hostkit_Test_Native.Exclusive_Hold;
   Started : Ada.Real_Time.Time;
   Waited  : Ada.Real_Time.Time_Span;
   Result  : Hostkit.Durability.Outcome := Hostkit.Durability.Failed;
   --  When the second holder let go: written by its task, read once the
   --  block that waits for the task has ended.
   Released : Ada.Real_Time.Time := Ada.Real_Time.Time_First;

   --  How much slower than a developer's machine the runner may be: CI sets
   --  HOSTKIT_TEST_TIME_SCALE (2 on its Windows and macOS runners), and a
   --  bound on elapsed time is that many times as long. 1 when unset.
   function Time_Scale return Positive is
   begin
      return Positive'Value (Hostkit.Environment.Value ("HOSTKIT_TEST_TIME_SCALE", "1"));
   exception
      when others =>
         return 1;
   end Time_Scale;

   procedure Clean_Up is
   begin
      Hostkit_Test_Native.Release (Held);
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Clean_Up;
begin
   --  Only Windows refuses an open because another holder did not share
   --  writing (a virus scanner on a file just written), and only there does
   --  Sync_File wait that out.
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Skip ("Test_A_Held_File_Is_Synced_Once_Let_Go", "only Windows refuses an open for a holder's share mode");
      return;
   end if;
   Write_File (Path, "held");
   Assert (Hostkit_Test_Native.Hold_Against_Writers (Path, Held), "the file is held against writers");
   Started := Ada.Real_Time.Clock;
   declare
      --  Lets go a moment after the sync has started trying; the block
      --  waits for it before it ends.
      task Holder;
      task body Holder is
      begin
         delay 0.15;
         Hostkit_Test_Native.Release (Held);
      end Holder;
   begin
      Result := Hostkit.Durability.Sync_File (Path);
      Waited := Ada.Real_Time.Clock - Started;
   end;
   Assert
     (Result = Hostkit.Durability.Synced,
      "a file held for a moment is synced once let go: " & Hostkit.Durability.Outcome'Image (Result));
   Assert
     (Waited >= Ada.Real_Time.Milliseconds (100),
      "the sync waited for the holder rather than reaching the file past it");
   --  The upper bound is loose on purpose: a loaded runner, and a virus
   --  scanner that holds the file just written a while longer, both stretch
   --  the wait without anything being wrong, and a second's bound failed on
   --  them. It catches only a sync that hangs.
   Assert
     (Waited < Ada.Real_Time.Milliseconds (5_000),
      "and tried again once it let go, rather than hanging on");

   --  The scanner's hold is on a file just written; the second sync of the
   --  same file meets only the test's own hold, so here the bound can be
   --  tight. Sync_File's whole retry schedule is 1.1 s (ten waits of 20 ms
   --  times the attempt); let go at 0.15 s, it opens the file at the attempt
   --  after that, under 0.1 s later. A sync that waited its retries out
   --  regardless would end some 0.95 s after the release. So the bound is
   --  counted from the release, not from the start -- a runner slow to
   --  start the holder no longer eats into it -- and is 0.4 s times the
   --  runner's time scale: still under 0.95 s at the scale of 2 CI's
   --  Windows runner sets, which is what tells the two apart (5 s never
   --  could).
   Assert (Hostkit_Test_Native.Hold_Against_Writers (Path, Held), "the file is held against writers again");
   Started := Ada.Real_Time.Clock;
   declare
      task Holder;
      task body Holder is
      begin
         delay 0.15;
         Hostkit_Test_Native.Release (Held);
         Released := Ada.Real_Time.Clock;
      end Holder;
   begin
      Result := Hostkit.Durability.Sync_File (Path);
      Waited := Ada.Real_Time.Clock - Started;
   end;
   declare
      After_Release : constant Ada.Real_Time.Time_Span := (Started + Waited) - Released;
   begin
      Clean_Up;
      Assert
        (Result = Hostkit.Durability.Synced,
         "a file held a second time is synced once let go: " & Hostkit.Durability.Outcome'Image (Result));
      Assert
        (Waited >= Ada.Real_Time.Milliseconds (100),
         "the second sync waited for the holder too");
      Assert
        (After_Release < Ada.Real_Time.Milliseconds (400 * Time_Scale),
         "and tried again soon after it let go, rather than waiting out its whole 1.1 s of retries; it took"
         & Duration'Image (Ada.Real_Time.To_Duration (After_Release)) & " s after the release");
   end;
exception
   when others =>
      Clean_Up;
      raise;
end Test_A_Held_File_Is_Synced_Once_Let_Go;
