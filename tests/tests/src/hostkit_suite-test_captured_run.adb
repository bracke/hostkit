separate (Hostkit_Suite)
procedure Test_Captured_Run (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   Out_Path : constant String := Ada.Directories.Compose (Scratch, "captured-out.txt");
   Err_Path : constant String := Ada.Directories.Compose (Scratch, "captured-err.txt");

   Empty   : Hostkit.String_Vectors.Vector;
   Outcome : Hostkit.Process.Process_Outcome;
begin
   Outcome :=
     Hostkit.Process.Run_Captured
       (Program     => Companion ("sleeper"),
        Arguments   => Empty,
        Stdout_Path => Out_Path,
        Stderr_Path => Err_Path);

   Assert (Outcome.Started, "the program started");
   Assert (not Outcome.Timed_Out, "and finished on its own");
   Assert (Outcome.Exit_Status = 0, "with its own exit status; was " & Outcome.Exit_Status'Image);

   --  The point of capturing is that the output is somewhere afterwards.
   Assert (File_Contains (Out_Path, "out-line"), "standard output was captured");
   Assert (File_Contains (Err_Path, "err-line"), "standard error was captured, separately");

   --  Both into one file: both there, neither written over the other.
   Outcome :=
     Hostkit.Process.Run_Captured
       (Program     => Companion ("sleeper"),
        Arguments   => Empty,
        Stdout_Path => Out_Path,
        Stderr_Path => Out_Path);
   Assert (Outcome.Started and then Outcome.Exit_Status = 0, "the program ran again");
   Assert (File_Contains (Out_Path, "out-line") and then File_Contains (Out_Path, "err-line"),
           "one file for both streams lost what one of them wrote");
end Test_Captured_Run;
