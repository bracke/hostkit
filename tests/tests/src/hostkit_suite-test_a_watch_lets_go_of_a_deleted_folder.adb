separate (Hostkit_Suite)
procedure Test_A_Watch_Lets_Go_Of_A_Deleted_Folder (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Directory : constant String := Ada.Directories.Compose (Scratch, "hostkit_watch_gone_dir");
   State     : Hostkit.Watch.Watch_State;
   Released  : Boolean := False;
   Ignored   : Boolean;
begin
   if Ada.Directories.Exists (Directory) then
      Ada.Directories.Delete_Tree (Directory);
   end if;

   Ada.Directories.Create_Directory (Directory);

   Hostkit.Watch.Watch_Path (State, Directory);
   Assert (Hostkit.Watch.Is_Active (State), "watching a real directory activates the native watch");
   Drain (State);

   --  The folder itself goes. Nothing will ever arrive on that watch again, so
   --  it must stop saying it is active -- the caller's cue to fall back -- and
   --  let go of the path, or watching the path again would be taken for
   --  "already watching" and do nothing.
   Ada.Directories.Delete_Tree (Directory);

   for Unused_Round in 1 .. Rounds loop
      Ignored := Hostkit.Watch.Poll (State);

      if not Hostkit.Watch.Is_Active (State) then
         Released := True;
         exit;
      end if;

      delay Settle;
   end loop;

   pragma Unreferenced (Ignored);
   Assert (Released, "a watch on a deleted folder still says it is active");

   --  The folder made again at the same path, and watched again: a fresh watch,
   --  which hears what happens in the new folder.
   Ada.Directories.Create_Directory (Directory);
   Hostkit.Watch.Watch_Path (State, Directory);
   Assert (Hostkit.Watch.Is_Active (State), "watching the path again, once the folder is back, arms a watch");

   Drain (State);
   Touch (Directory, "after.txt");
   Assert (Wait_For_Change (State), "the fresh watch notices a change in the new folder");

   Hostkit.Watch.Release (State);
   Ada.Directories.Delete_Tree (Directory);
exception
   when others =>
      Hostkit.Watch.Release (State);

      if Ada.Directories.Exists (Directory) then
         Ada.Directories.Delete_Tree (Directory);
      end if;

      raise;
end Test_A_Watch_Lets_Go_Of_A_Deleted_Folder;
