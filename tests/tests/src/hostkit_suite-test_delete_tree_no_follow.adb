separate (Hostkit_Suite)
procedure Test_Delete_Tree_No_Follow
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   Root : constant String := Ada.Directories.Compose (Scratch, "hk-delete-tree");
   Child : constant String := Ada.Directories.Compose (Root, "child");
   Outside : constant String := Ada.Directories.Compose (Scratch, "hk-delete-outside");
   Outside_File : constant String := Ada.Directories.Compose (Outside, "kept.txt");
   Link : constant String := Ada.Directories.Compose (Root, "outside-link");
begin
   Delete_Tree_If_Present (Root);
   Delete_Tree_If_Present (Outside);
   Ada.Directories.Create_Path (Child);
   Ada.Directories.Create_Path (Outside);
   Write_File (Ada.Directories.Compose (Child, "payload.txt"), "payload");
   --  Read-only, as git leaves its objects: Windows refuses a plain
   --  delete of one, and the tree must still go.
   Write_File (Ada.Directories.Compose (Child, "read-only.txt"), "kept read-only");
   GNAT.OS_Lib.Set_Read_Only (Ada.Directories.Compose (Child, "read-only.txt"));
   Write_File (Outside_File, "keep");
   declare
      Linked : constant Boolean := Hostkit.Fs.Create_Link (Outside, Link);
   begin
      Assert
        (Hostkit.Fs.Delete_Tree_No_Follow (Root) = Hostkit.Fs.Tree_Deleted,
         "a held tree is deleted");
      Assert (not Ada.Directories.Exists (Root), "the requested tree is gone");
      Assert (Ada.Directories.Exists (Outside_File), "a linked outside tree is untouched");
      if Linked then
         Assert (not Hostkit.Fs.Is_Link (Link), "the link itself is gone with the tree");
      else
         Links_Refused ("Delete_Tree_No_Follow, a link out of the tree");
      end if;
   end;
   Assert
     (Hostkit.Fs.Delete_Tree_No_Follow (Root) = Hostkit.Fs.Tree_Delete_Failed,
      "a missing tree is not reported as deleted");
   Delete_Tree_If_Present (Outside);
exception
   when others =>
      if Hostkit.Fs.Is_Link (Link) then
         declare
            Ignored : constant Boolean := Hostkit.Fs.Delete_Link (Link);
         begin
            null;
         end;
      end if;
      Delete_Tree_If_Present (Root);
      Delete_Tree_If_Present (Outside);
      raise;
end Test_Delete_Tree_No_Follow;
