separate (Hostkit_Shell_Cases)
procedure Test_Assign_Moves_This_Programs_Own_Writing
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Room : constant String :=
     Hostkit.Fs.Create_Temporary_Directory ("hostkit-assign-test");

   Path : constant String := Hostkit.Fs.Join (Room, "captured.txt");

   Marker : constant String := "written through the language";

   Saved   : Hostkit.Descriptors.Descriptor;
   Opened  : Hostkit.Descriptors.Descriptor;
   Moved   : Boolean := False;
   Put_Back : Boolean := False;

   Held : Ada.Strings.Unbounded.Unbounded_String;
begin
   Saved := Hostkit.Descriptors.Duplicate
              (Hostkit.Descriptors.Standard_Output);

   Assert (Hostkit.Descriptors.Is_Valid (Saved),
           "standard output could not be saved");

   Assert (Hostkit.Descriptors.Open_File
             (Path, Hostkit.Descriptors.Open_Write_Truncate, Opened),
           "the capture file would not open");

   Moved := Hostkit.Descriptors.Assign
              (Opened, Hostkit.Descriptors.Stream_Output);

   if Moved then
      Ada.Text_IO.Put_Line (Marker);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
   end if;

   Put_Back := Hostkit.Descriptors.Assign
                 (Saved, Hostkit.Descriptors.Stream_Output);

   Hostkit.Descriptors.Close (Opened);
   Hostkit.Descriptors.Close (Saved);

   --  Read after the stream is back, so that a failure has somewhere to be
   --  reported to.
   declare
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Strings.Unbounded.Append
           (Held, Ada.Text_IO.Get_Line (File));
      end loop;

      Ada.Text_IO.Close (File);
   exception
      when others =>
         null;
   end;

   begin
      Ada.Directories.Delete_Tree (Room);
   exception
      when others =>
         null;
   end;

   Assert (Moved, "a stream this host has could not be assigned");
   Assert (Put_Back, "the stream could not be put back");

   Assert (Ada.Strings.Fixed.Index
             (Ada.Strings.Unbounded.To_String (Held), Marker) > 0,
           "assigning a stream did not move this program's own writing: ["
           & Ada.Strings.Unbounded.To_String (Held) & "]");
end Test_Assign_Moves_This_Programs_Own_Writing;
