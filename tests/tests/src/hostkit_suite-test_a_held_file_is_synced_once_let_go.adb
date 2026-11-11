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
   Ada.Directories.Delete_File (Path);
   Assert
     (Result = Hostkit.Durability.Synced,
      "a file held for a moment is synced once let go: " & Hostkit.Durability.Outcome'Image (Result));
   Assert
     (Waited >= Ada.Real_Time.Milliseconds (100),
      "the sync waited for the holder rather than reaching the file past it");
   Assert
     (Waited < Ada.Real_Time.Milliseconds (1_000),
      "and tried again soon after it let go, not only at the end of its retries");
end Test_A_Held_File_Is_Synced_Once_Let_Go;
