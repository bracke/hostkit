separate (Hostkit_Shell_Cases)
procedure Test_A_Launch_Starts_In_Its_Working_Directory
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Room      : constant String :=
     Hostkit.Fs.Create_Temporary_Directory ("hostkit-launch-dir-test");
   Answer    : constant String := Hostkit.Fs.Join (Room, "answer");
   Arguments : Hostkit.String_Vectors.Vector;
   Reported  : Ada.Strings.Unbounded.Unbounded_String;
begin
   Arguments.Append (Ada.Strings.Unbounded.To_Unbounded_String (Answer));
   Assert (Hostkit.Process.Launch (Companion ("where_started"), Arguments, Working_Directory => Room),
           "the launch in a working directory did not start");

   for Attempt in 1 .. 200 loop
      exit when Ada.Directories.Exists (Answer & ".done");
      delay 0.05;
   end loop;
   Assert (Ada.Directories.Exists (Answer & ".done"), "the launched program never answered");

   declare
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Answer & ".done");
      Reported := Ada.Strings.Unbounded.To_Unbounded_String (Ada.Text_IO.Get_Line (File));
      Ada.Text_IO.Close (File);
   end;
   Assert (Hostkit.Fs.Real_Path (Ada.Strings.Unbounded.To_String (Reported)) = Hostkit.Fs.Real_Path (Room),
           "the program started in " & Ada.Strings.Unbounded.To_String (Reported) & ", not " & Room);
   Assert (Ada.Directories.Current_Directory /= Room, "the launch left this process where it was");
   Ada.Directories.Delete_Tree (Room);
exception
   when others =>
      if Ada.Directories.Exists (Room) then
         Ada.Directories.Delete_Tree (Room);
      end if;
      raise;
end Test_A_Launch_Starts_In_Its_Working_Directory;
