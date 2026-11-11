separate (Hostkit_Suite)
procedure Test_The_Watch_Notices_Changes (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Directory : constant String := Ada.Directories.Compose (Scratch, "hostkit_watch_test_dir");
   State     : Hostkit.Watch.Watch_State;
begin
   if Ada.Directories.Exists (Directory) then
      Ada.Directories.Delete_Tree (Directory);
   end if;

   Ada.Directories.Create_Directory (Directory);

   Hostkit.Watch.Watch_Path (State, Directory);
   Assert (Hostkit.Watch.Is_Active (State), "watching a real directory activates the native watch");

   Drain (State);
   Assert (not Hostkit.Watch.Poll (State), "a directory nobody touched reports no change");

   Touch (Directory, "created.txt");
   Assert (Wait_For_Change (State), "creating a file is noticed");
   Assert (not Hostkit.Watch.Poll (State), "the change is consumed, not reported twice");

   --  A file written while it stays open -- a download growing -- where
   --  the host's watch says it sees writes within files.
   if Hostkit.Watch.Sees_File_Writes then
      declare
         Output : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open
           (Output, Ada.Text_IO.Append_File, Ada.Directories.Compose (Directory, "created.txt"));
         Drain (State);
         Ada.Text_IO.Put_Line (Output, "more");
         Ada.Text_IO.Flush (Output);
         Assert (Wait_For_Change (State), "a write into an open file is noticed");
         Ada.Text_IO.Close (Output);
         Drain (State);
      end;
   end if;

   Ada.Directories.Delete_File (Ada.Directories.Compose (Directory, "created.txt"));
   Assert (Wait_For_Change (State), "deleting a file is noticed");

   Assert (Hostkit.Watch.Event_Count (State) > 0, "events are counted");

   Hostkit.Watch.Release (State);
   Assert (not Hostkit.Watch.Is_Active (State), "release deactivates the watch");

   Ada.Directories.Delete_Tree (Directory);
end Test_The_Watch_Notices_Changes;
