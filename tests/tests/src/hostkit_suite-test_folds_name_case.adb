separate (Hostkit_Suite)
procedure Test_Folds_Name_Case (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Path : constant String := Ada.Directories.Compose (Scratch, "CaseProbe");
   File : Ada.Text_IO.File_Type;
begin
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Close (File);
   declare
      Found_Folded : constant Boolean := Ada.Directories.Exists (Ada.Directories.Compose (Scratch, "caseprobe"));
   begin
      Ada.Directories.Delete_File (Path);
      Assert
        (Hostkit.Fs.Folds_Name_Case (Scratch) = Found_Folded,
         "Folds_Name_Case says what the volume does: a name in other case "
         & (if Found_Folded then "finds" else "does not find") & " the file");
   end;
end Test_Folds_Name_Case;
