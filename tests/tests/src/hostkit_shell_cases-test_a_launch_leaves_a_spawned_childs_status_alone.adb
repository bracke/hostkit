separate (Hostkit_Shell_Cases)
procedure Test_A_Launch_Leaves_A_Spawned_Childs_Status_Alone
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Room    : constant String := Hostkit.Fs.Create_Temporary_Directory ("hostkit-reaper-test");
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;

   --  The where_started companion's one argument: the file it writes, and
   --  renames to Marker & ".done", just before it exits.
   function Told (Marker : String) return Hostkit.String_Vectors.Vector is
      Arguments : Hostkit.String_Vectors.Vector;
   begin
      Arguments.Append (To_Unbounded_String (Hostkit.Fs.Join (Room, Marker)));
      return Arguments;
   end Told;

   --  Wait until the companion told Marker has written it -- the last thing
   --  it does -- and then a moment more for it to have exited. Its exit is
   --  what the scenario needs; waiting for it by Spawn.Wait would collect
   --  it, which is the one thing the spawned child must not be until the end.
   procedure Await_Exit (Marker : String) is
      Done : constant String := Hostkit.Fs.Join (Room, Marker) & ".done";
   begin
      for Attempt in 1 .. 400 loop
         exit when Ada.Directories.Exists (Done);
         delay 0.05;
      end loop;
      Assert (Ada.Directories.Exists (Done), "the companion told " & Marker & " never finished");
      delay 0.25;
   end Await_Exit;
begin
   Assert (Hostkit.Spawn.Start (Companion ("where_started"), Told ("spawned"), Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the companion did not start it");

   --  The order is made, not hoped for. The spawned child has finished and
   --  waits, uncollected, for its status to be asked for, before either
   --  launch. Each launch wakes the reaper; the second wakes it after the
   --  first launched child has finished too, so the reaper has something of
   --  its own to collect while the spawned child's status is there for the
   --  taking -- a reaper that collected any finished child would take it.
   --  On a loaded runner a fixed delay could end before the children did,
   --  and the test would pass with that bug.
   Await_Exit ("spawned");
   Assert (Hostkit.Process.Launch (Companion ("where_started"), Told ("first")), "the first launch did not start");
   Await_Exit ("first");
   Assert (Hostkit.Process.Launch (Companion ("where_started"), Told ("second")), "the second launch did not start");
   Await_Exit ("second");

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the spawned child failed");
   Hostkit.Spawn.Release (Child);
   Ada.Directories.Delete_Tree (Room);
   Assert (Result.State = Hostkit.Spawn.Wait_Exited,
           "the spawned child's status was taken by a launch's reaper: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));
   Assert (Result.Exit_Code = 0,
           "the spawned child's exit status was lost; got"
           & Integer'Image (Result.Exit_Code));
exception
   when others =>
      if Ada.Directories.Exists (Room) then
         Ada.Directories.Delete_Tree (Room);
      end if;
      raise;
end Test_A_Launch_Leaves_A_Spawned_Childs_Status_Alone;
