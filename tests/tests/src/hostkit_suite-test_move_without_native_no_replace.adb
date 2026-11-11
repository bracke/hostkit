separate (Hostkit_Suite)
procedure Test_Move_Without_Native_No_Replace
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   use type Hostkit.Fs.Move_Outcome;

   pragma Unreferenced (T);

   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("hk-move-fallback");
   Source   : constant String := Ada.Directories.Compose (Root, "source.txt");
   Target   : constant String := Ada.Directories.Compose (Root, "target.txt");
   Taken    : constant String := Ada.Directories.Compose (Root, "taken.txt");
   Dangling : constant String := Ada.Directories.Compose (Root, "dangling");
   Folder   : constant String := Ada.Directories.Compose (Root, "folder");
   Moved_To : constant String := Ada.Directories.Compose (Root, "moved");
   Empty    : constant String := Ada.Directories.Compose (Root, "empty");

   function Move (From, To : String) return Hostkit.Fs.Move_Outcome is
     (Hostkit.Fs.Move_Without_Native_No_Replace (From, To));
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (Move (Source, Target) = Hostkit.Fs.Move_Unsupported, "Windows has no POSIX fallback");
      Delete_Tree_If_Present (Root);
      return;
   end if;
   begin
      Write_File (Source, "payload");
      Write_File (Taken, "keep");
      Ada.Directories.Create_Directory (Folder);
      Write_File (Ada.Directories.Compose (Folder, "inner.txt"), "inner");
      Ada.Directories.Create_Directory (Empty);
      Assert (Hostkit.Fs.Create_Link ("nowhere", Dangling), "create a dangling link");

      Assert (Move (Ada.Directories.Compose (Root, "absent"), Target) = Hostkit.Fs.Move_Refused,
              "a missing source is refused");
      Assert (Move (Source, Taken) = Hostkit.Fs.Move_Refused, "an occupied target is refused");
      Assert (Move (Source, Dangling) = Hostkit.Fs.Move_Refused, "a dangling link at the target is refused");
      Assert (Hostkit.Fs.Is_Link (Dangling), "the refused move leaves the dangling link");
      Assert (Move (Folder, Empty) = Hostkit.Fs.Move_Refused, "a folder never replaces an empty folder");
      Assert (Ada.Directories.Exists (Source) and then Ada.Directories.Exists (Folder),
              "refused moves leave their sources");

      Assert (Move (Source, Target) = Hostkit.Fs.Moved, "a file moves to a free name");
      Assert (Ada.Directories.Exists (Target) and then not Ada.Directories.Exists (Source),
              "the moved file is at the target only");
      Assert (Move (Folder, Moved_To) = Hostkit.Fs.Moved, "a folder moves to a free name");
      Assert (Ada.Directories.Exists (Ada.Directories.Compose (Moved_To, "inner.txt"))
              and then not Ada.Directories.Exists (Folder),
              "the moved folder keeps its contents at the target only");
      Assert (Hostkit.Fs.Delete_Link (Dangling), "remove the dangling link");
   exception
      when others =>
         if Hostkit.Fs.Delete_Link (Dangling) then
            null;
         end if;
         Delete_Tree_If_Present (Root);
         raise;
   end;

   Delete_Tree_If_Present (Root);
end Test_Move_Without_Native_No_Replace;
