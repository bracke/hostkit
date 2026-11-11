separate (Hostkit_Shell_Cases)
procedure Test_What_Starts_Is_Narrower_Than_What_Runs
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Room : constant String :=
     Hostkit.Fs.Create_Temporary_Directory ("hostkit-starts-test");

   procedure Write (Name : String);

   procedure Write (Name : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create
        (File, Ada.Text_IO.Out_File, Hostkit.Fs.Join (Room, Name));
      Ada.Text_IO.Put_Line (File, "rem nothing");
      Ada.Text_IO.Close (File);
   end Write;

   Batch  : constant String := Hostkit.Fs.Join (Room, "thing.bat");
   Script : constant String := Hostkit.Fs.Join (Room, "thing.ps1");
   Plain  : constant String := Hostkit.Fs.Join (Room, "thing.txt");
begin
   Write ("thing.bat");
   Write ("thing.ps1");
   Write ("thing.txt");

   --  A file that is not a program on any host.
   Assert (not Hostkit.Fs.Starts_When_Named (Plain),
           "a plain text file was said to start");

   if Hostkit.Fs.Is_Executable (Batch) then
      --  The host that calls these programs. It starts the batch file, by
      --  running the interpreter for it, and does not start the other.
      Assert (Hostkit.Fs.Starts_When_Named (Batch),
              "a batch file was said not to start on a host that runs one");
      Assert (not Hostkit.Fs.Starts_When_Named (Script),
              "a file nothing starts from a name was said to start");
   else
      --  A host with no such notion: neither is a program, and both
      --  questions agree.
      Assert (not Hostkit.Fs.Starts_When_Named (Batch),
              "a file this host does not call a program was said to start");
   end if;

   --  And the suite's own binary, which every host starts.
   Assert (Hostkit.Fs.Starts_When_Named (Ada.Command_Line.Command_Name),
           "the running program was said not to start");

   Ada.Directories.Delete_Tree (Room);
end Test_What_Starts_Is_Narrower_Than_What_Runs;
