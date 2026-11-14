with Hostkit_Test_Native;

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

   --  Wait until the companion told Marker has exited. Its exit is what the
   --  scenario needs; waiting for it by Spawn.Wait would collect it, which
   --  is the one thing the spawned child must not be until the end. So the
   --  wait is waitid's WNOWAIT (Hostkit_Test_Native), on the process id the
   --  companion wrote beside its answer -- the last thing it does. A launched
   --  child the reaper has already collected is done too (Not_A_Child); the
   --  spawned one must not be. Windows has no reaping and no such wait, and
   --  gives the companion a moment after its answer instead.
   procedure Await_Exit (Marker : String; Collected_Is_Fine : Boolean) is
      Done   : constant String := Hostkit.Fs.Join (Room, Marker) & ".done";
      File   : Ada.Text_IO.File_Type;
      Pid    : Integer;
      Waited : Hostkit_Test_Native.Exit_Wait;
   begin
      for Attempt in 1 .. 400 loop
         exit when Ada.Directories.Exists (Done);
         delay 0.05;
      end loop;
      Assert (Ada.Directories.Exists (Done), "the companion told " & Marker & " never finished");
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Done);
      Ada.Text_IO.Skip_Line (File);
      Pid := Integer'Value (Ada.Text_IO.Get_Line (File));
      Ada.Text_IO.Close (File);
      Waited := Hostkit_Test_Native.Await_Exit_Uncollected (Pid);
      case Waited is
         when Hostkit_Test_Native.Exited =>
            null;
         when Hostkit_Test_Native.Not_A_Child =>
            Assert (Collected_Is_Fine, "the companion told " & Marker & " was collected before its time");
         when Hostkit_Test_Native.Cannot_Wait =>
            delay 0.25;
      end case;
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
   --  and the test would pass with that bug; Await_Exit waits for the exit
   --  itself.
   Await_Exit ("spawned", Collected_Is_Fine => False);
   Assert (Hostkit.Process.Launch (Companion ("where_started"), Told ("first")), "the first launch did not start");
   Await_Exit ("first", Collected_Is_Fine => True);
   Assert (Hostkit.Process.Launch (Companion ("where_started"), Told ("second")), "the second launch did not start");
   Await_Exit ("second", Collected_Is_Fine => True);

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
