with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.OS_Lib;

with Hostkit.Parent_Watch;

--  Asks to end with its parent, writes its process id and whether that was
--  arranged to the file it is given, and sleeps far longer than a case
--  waits: if it is still there when its parent has gone, the watch failed.
procedure Watched is
   Arranged : constant Boolean := Hostkit.Parent_Watch.End_With_Parent;
   File     : Ada.Text_IO.File_Type;
   Done     : Boolean;
begin
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Ada.Command_Line.Argument (1) & ".tmp");
   Ada.Text_IO.Put_Line (File, Integer'Image (GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id)));
   Ada.Text_IO.Put_Line (File, (if Arranged then "arranged" else "not arranged"));
   Ada.Text_IO.Close (File);
   GNAT.OS_Lib.Rename_File (Ada.Command_Line.Argument (1) & ".tmp", Ada.Command_Line.Argument (1), Success => Done);
   if Done then
      delay 30.0;
   end if;
end Watched;
