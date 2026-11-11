separate (Hostkit_Suite)
procedure Test_Windows_Attributes_Are_Copied
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Source : constant String := Ada.Directories.Compose (Scratch, "hostkit-attr-source");
   Target : constant String := Ada.Directories.Compose (Scratch, "hostkit-attr-target");
   File   : Ada.Text_IO.File_Type;
   Done   : Boolean;
begin
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Skip ("Test_Windows_Attributes_Are_Copied", "needs Windows file attributes");
      return;
   end if;
   for Index in 1 .. 2 loop
      declare
         Name : constant String := (if Index = 1 then Source else Target);
      begin
         if Ada.Directories.Exists (Name) then
            Ada.Directories.Delete_File (Name);
         end if;
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Name);
         Ada.Text_IO.Close (File);
      end;
   end loop;
   declare
      use type GNAT.OS_Lib.String_Access;
      Attrib : constant GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("attrib.exe");
   begin
      Assert (Attrib /= null, "attrib.exe is on the path");
      GNAT.OS_Lib.Spawn (Attrib.all, GNAT.OS_Lib.Argument_String_To_List ("+H " & Source).all, Done);
      Assert (Done and then Hostkit.Fs.Is_Hidden (Source), "the source is hidden");
      Assert
        (Hostkit.Metadata_Copy.Apply (Hostkit.Metadata_Copy.Capture (Source), Target, Preserve_Ownership => False),
         "its metadata is applied to the copy");
      Assert (Hostkit.Fs.Is_Hidden (Target), "and the copy is hidden too");
      GNAT.OS_Lib.Spawn (Attrib.all, GNAT.OS_Lib.Argument_String_To_List ("-H " & Source).all, Done);
      Assert (Done, "the source is shown again");
      GNAT.OS_Lib.Spawn (Attrib.all, GNAT.OS_Lib.Argument_String_To_List ("-H " & Target).all, Done);
      Assert (Done, "and so is the copy");
   end;
   Ada.Directories.Delete_File (Source);
   Ada.Directories.Delete_File (Target);
end Test_Windows_Attributes_Are_Copied;
