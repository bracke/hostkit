separate (Hostkit_Suite)
procedure Test_Captured_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   In_Path  : constant String := Ada.Directories.Compose (Scratch, "captured-in.txt");
   Out_Path : constant String := Ada.Directories.Compose (Scratch, "captured-in-out.txt");
   Missing  : constant String := Ada.Directories.Compose (Scratch, "captured-in-absent.txt");

   Empty   : Hostkit.String_Vectors.Vector;
   Outcome : Hostkit.Process.Process_Outcome;
   File    : Ada.Text_IO.File_Type;
begin
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, In_Path);
   Ada.Text_IO.Put_Line (File, "secret-from-a-file");
   Ada.Text_IO.Close (File);

   if Ada.Directories.Exists (Missing) then
      Ada.Directories.Delete_File (Missing);
   end if;

   --  A program that asks for a secret on standard input cannot be run at
   --  all without this: there is no terminal to answer it from.
   Outcome :=
     Hostkit.Process.Run_Captured
       (Program     => Companion ("echoer"),
        Arguments   => Empty,
        Stdin_Path  => In_Path,
        Stdout_Path => Out_Path,
        --  A deadline, because the way this fails is by not failing: a
        --  program left reading the caller's own input waits for ever, and
        --  a suite that hangs says less than one that stops and reports.
        Timeout_Ms  => 20_000);

   Assert (Outcome.Started, "the program started with a file on its input");
   Assert
     (not Outcome.Timed_Out,
      "and finished rather than waiting on input that never came");
   Assert
     (Outcome.Exit_Status = 0,
      "and found something to read; exit was " & Outcome.Exit_Status'Image);
   Assert
     (File_Contains (Out_Path, "read:secret-from-a-file"),
      "and read what the file said, rather than the caller's own input");

   --  Told to read a file that is not there, the launch has to fail. Falling
   --  back to the caller's input would leave a password prompt waiting on a
   --  terminal that may not exist.
   Outcome :=
     Hostkit.Process.Run_Captured
       (Program    => Companion ("echoer"),
        Arguments  => Empty,
        Stdin_Path => Missing);

   Assert
     (not Outcome.Started,
      "an input file that is not there fails the launch rather than falling back");
end Test_Captured_Input;
