separate (Hostkit_Suite)
procedure Test_Group_Ends_With_Leader (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   use type Hostkit.Process.Presence;

   Pid_Path  : constant String := Ada.Directories.Compose (Scratch, "group-left.pid");
   Arguments : Hostkit.String_Vectors.Vector;
   Outcome   : Hostkit.Process.Process_Outcome;
   File      : Ada.Text_IO.File_Type;
   Child     : Integer := 0;
   Gone      : Boolean := False;
begin
   if Hostkit.Host.Current /= Hostkit.Host.Linux then
      Skip ("Test_Group_Ends_With_Leader", "a group ending with its leader is checked on Linux");
      return;
   end if;
   Arguments.Append (To_Unbounded_String ("-c"));
   Arguments.Append (To_Unbounded_String ("sleep 30 & echo $! > " & Pid_Path & "; exit 0"));
   Outcome :=
     Hostkit.Process.Run_Captured
       (Program     => "/bin/sh",
        Arguments   => Arguments,
        Stdin_Path  => "/dev/null",
        Timeout_Ms  => 10_000,
        Whole_Group => True);
   Assert (Outcome.Started and then not Outcome.Timed_Out and then Outcome.Exit_Status = 0,
           "the shell did not end on its own");
   Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Pid_Path);
   Child := Integer'Value (Ada.Text_IO.Get_Line (File));
   Ada.Text_IO.Close (File);
   for Try in 1 .. 100 loop
      Gone := Hostkit.Process.Presence_Of (Child) = Hostkit.Process.Absent;
      exit when Gone;
      delay 0.01;
   end loop;
   Assert (Gone, "what the shell left running outlived it");
end Test_Group_Ends_With_Leader;
