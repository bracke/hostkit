separate (Hostkit_Suite)
procedure Test_Clean_Wrapper (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   Out_Path  : constant String := Ada.Directories.Compose (Scratch, "wrapper-env.txt");
   Arguments : Hostkit.String_Vectors.Vector;
   Outcome   : Hostkit.Process.Process_Outcome;
   File      : Ada.Text_IO.File_Type;
   Seen      : Unbounded_String;
begin
   if Hostkit.Host.Current /= Hostkit.Host.Linux then
      Skip ("Test_Clean_Wrapper", "the wrapper's environment is read back through Linux /proc");
      return;
   end if;
   Ada.Environment_Variables.Set ("HOSTKIT_WRAPPER_SECRET", "not-for-children");
   Arguments.Append (To_Unbounded_String ("-c"));
   Arguments.Append (To_Unbounded_String ("tr '\000' '\n' < /proc/$PPID/environ"));
   Outcome :=
     Hostkit.Process.Run_Captured
       (Program       => "/bin/sh",
        Arguments     => Arguments,
        Stdin_Path    => "/dev/null",
        Stdout_Path   => Out_Path,
        Timeout_Ms    => 10_000,
        Whole_Group   => True,
        Clean_Wrapper => True);
   Ada.Environment_Variables.Clear ("HOSTKIT_WRAPPER_SECRET");
   Assert (Outcome.Started and then Outcome.Exit_Status = 0, "the program did not run");
   Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Out_Path);
   while not Ada.Text_IO.End_Of_File (File) loop
      Append (Seen, Ada.Text_IO.Get_Line (File) & ASCII.LF);
   end loop;
   Ada.Text_IO.Close (File);
   Assert (Ada.Strings.Fixed.Index (To_String (Seen), "HOSTKIT_WRAPPER_SECRET") = 0
           and then Ada.Strings.Fixed.Index (To_String (Seen), "PATH=") > 0,
           "the wrapper held the caller's environment: " & To_String (Seen));
end Test_Clean_Wrapper;
