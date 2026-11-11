separate (Hostkit_Suite)
procedure Test_Change_Stamp
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path      : constant String := Ada.Directories.Compose (Scratch, "hk-change-stamp.txt");
   Available : Boolean;
begin
   Write_File (Path, "first");
   declare
      Before : constant String := Hostkit.Metadata.Change_Stamp (Path, Available);
   begin
      Assert (Available and then Before /= "", "a file's change stamp is given");
      Assert (Hostkit.Metadata.Change_Stamp (Path, Available) = Before and then Available,
              "an untouched file keeps its stamp");
      --  The same size, written again: only the times tell it.
      delay 0.05;
      Write_File (Path, "again");
      Assert (Hostkit.Metadata.Change_Stamp (Path, Available) /= Before and then Available,
              "a file rewritten to the same size has another stamp");
   end;
   Ada.Directories.Delete_File (Path);
   declare
      Gone : constant String := Hostkit.Metadata.Change_Stamp (Path, Available);
   begin
      Assert (not Available and then Gone = "", "a missing file has no stamp");
   end;
end Test_Change_Stamp;
