separate (Hostkit_Suite)
procedure Test_Group_Stops_Whole (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   use type Ada.Directories.File_Size;
   use type Hostkit.Process.Presence;

   Pid_Path  : constant String := Ada.Directories.Compose (Scratch, "group-child.pid");
   Arguments : Hostkit.String_Vectors.Vector;
   Outcome   : Hostkit.Process.Process_Outcome;
   File      : Ada.Text_IO.File_Type;
   Child     : Integer := 0;
   Gone      : Boolean := False;

   --  Windows: stopped once the leader has said what it started, rather
   --  than on a deadline PowerShell's start-up could outrun.
   function Recorded return Boolean is
     (Ada.Directories.Exists (Pid_Path) and then Ada.Directories.Size (Pid_Path) > 0);
begin
   if Ada.Directories.Exists (Pid_Path) then
      Ada.Directories.Delete_File (Pid_Path);
   end if;
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      --  A job is the group: stopping it stops what the leader started.
      Outcome :=
        Hostkit.Process.Run_Captured
          (Program     => Power_Shell,
           Arguments   => Windows_Leader (Pid_Path, "Start-Sleep -Seconds 60"),
           Stdin_Path  => Hostkit.Fs.Null_Device,
           Stdout_Path => Ada.Directories.Compose (Scratch, "group-child.out"),
           Timeout_Ms  => 60_000,
           Cancelled   => Recorded'Unrestricted_Access,
           Whole_Group => True);
      Assert (Outcome.Started and then Outcome.Timed_Out, "the leader was not stopped once it had started a child");
   elsif not Ada.Directories.Exists ("/bin/sh") then
      --  Where there is no POSIX shell there is no group to stop.
      Skip ("Test_Group_Stops_Whole", "no POSIX shell to start a group with");
      return;
   else
      Arguments.Append (To_Unbounded_String ("-c"));
      Arguments.Append (To_Unbounded_String ("sleep 30 & echo $! > " & Pid_Path & "; wait"));
      Outcome :=
        Hostkit.Process.Run_Captured
          (Program     => "/bin/sh",
           Arguments   => Arguments,
           Stdin_Path  => "/dev/null",
           Timeout_Ms  => 500,
           Whole_Group => True);
      Assert (Outcome.Started and then Outcome.Timed_Out, "the shell was not stopped on its deadline");
   end if;

   Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Pid_Path);
   Child := Integer'Value (Ada.Text_IO.Get_Line (File));
   Ada.Text_IO.Close (File);
   for Try in 1 .. 100 loop
      Gone := Hostkit.Process.Presence_Of (Child) = Hostkit.Process.Absent;
      exit when Gone;
      delay 0.01;
   end loop;
   Assert (Gone, "what the shell started outlived it");
end Test_Group_Stops_Whole;
