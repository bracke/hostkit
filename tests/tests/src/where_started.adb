with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;

--  Writes the directory it was started in to the file named by its first
--  argument, then renames it to that name plus ".done", so a reader never
--  sees a half-written answer.
--
--  For the question a launch test cannot otherwise ask: a program launched
--  in a working directory has to say where it found itself.
procedure Where_Started is
begin
   if Ada.Command_Line.Argument_Count < 1 then
      Ada.Command_Line.Set_Exit_Status (5);
      return;
   end if;

   declare
      Answer : constant String := Ada.Command_Line.Argument (1);
      File   : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Answer);
      Ada.Text_IO.Put_Line (File, Ada.Directories.Current_Directory);
      Ada.Text_IO.Close (File);
      Ada.Directories.Rename (Answer, Answer & ".done");
   end;
end Where_Started;
