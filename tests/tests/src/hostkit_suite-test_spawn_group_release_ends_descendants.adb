separate (Hostkit_Suite)
procedure Test_Spawn_Group_Release_Ends_Descendants
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Process.Presence;
   use type Hostkit.Spawn.Spawn_Outcome;
   use type Hostkit.Spawn.Wait_State;

   Pid_Path : constant String := Ada.Directories.Compose (Scratch, "spawn-group-left.pid");
   Options  : Hostkit.Spawn.Options;
   Child    : Hostkit.Spawn.Process_Handle;
   Result   : Hostkit.Spawn.Status;
   File     : Ada.Text_IO.File_Type;
   Left     : Integer;
   Gone     : Boolean := False;
begin
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Skip
        ("Test_Spawn_Group_Release_Ends_Descendants",
         "Job Object group release exists only on Windows");
      return;
   end if;
   if Ada.Directories.Exists (Pid_Path) then
      Ada.Directories.Delete_File (Pid_Path);
   end if;

   Options.Group := Hostkit.Spawn.Group_New;
   Assert
     (Hostkit.Spawn.Start
        (Power_Shell, Windows_Leader (Pid_Path, "exit 0"), Options, Child)
        = Hostkit.Spawn.Spawn_Ok,
      "the group leader did not start");
   Assert
     (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result)
      and then Result.State = Hostkit.Spawn.Wait_Exited,
      "the group leader did not finish");

   Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Pid_Path);
   Left := Integer'Value (Ada.Text_IO.Get_Line (File));
   Ada.Text_IO.Close (File);
   Hostkit.Spawn.Release (Child);

   for Try in 1 .. 100 loop
      Gone := Hostkit.Process.Presence_Of (Left) = Hostkit.Process.Absent;
      exit when Gone;
      delay 0.01;
   end loop;
   Assert (Gone, "a descendant outlived release of its Group_New leader");
   Ada.Directories.Delete_File (Pid_Path);
end Test_Spawn_Group_Release_Ends_Descendants;
