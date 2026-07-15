with AUnit.Assertions;
with AUnit;
with AUnit.Test_Cases;

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces.C.Strings;
with Ada.Strings.Unbounded;

with Hostkit;
with Hostkit.Fs;
with Hostkit.Process;
with Hostkit.Shell;

package body Hostkit_Suite is
   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   --  The suite's own directory: noop and failing are built beside it.
   function Companion (Name : String) return String is
      Self : constant String := Ada.Command_Line.Command_Name;
      Dir  : constant String := Ada.Directories.Containing_Directory (Self);
   begin
      if Ada.Directories.Exists (Ada.Directories.Compose (Dir, Name & ".exe")) then
         return Ada.Directories.Compose (Dir, Name & ".exe");
      end if;

      return Ada.Directories.Compose (Dir, Name);
   exception
      when others =>
         return Name;
   end Companion;

   --  Somewhere to put captured output. The host's own temporary directory, because /tmp
   --  is not a place Windows has.
   function Scratch return String is
      Base : constant String :=
        (if Ada.Environment_Variables.Exists ("TMPDIR")
         then Ada.Environment_Variables.Value ("TMPDIR")
         elsif Ada.Environment_Variables.Exists ("TEMP")
         then Ada.Environment_Variables.Value ("TEMP")
         else "/tmp");
   begin
      return Base;
   end Scratch;

   function File_Contains (Path : String; Text : String) return Boolean is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            if Ada.Strings.Fixed.Index (Line, Text) > 0 then
               Ada.Text_IO.Close (File);
               return True;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);
      return False;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end File_Contains;

   procedure Test_Quoting (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  The shell is asked once and everything follows from it, so that the quoting
      --  can never disagree with the shell it is quoting for -- which is exactly the
      --  bug this replaced: cmd, handed arguments in sh's single quotes.
      if Hostkit.Shell.Is_Command_Shell then
         declare
            --  One double-quote character. Spelling the expectation out of these reads,
            --  and a literal thicket of doubled quotes does not -- which is exactly how
            --  this assertion came to be wrong.
            DQ : constant String := """";
         begin
            Assert (Hostkit.Shell.Command_Option = "/C", "cmd is introduced with /C");
            Assert
              (Hostkit.Shell.Quote ("a b") = DQ & "a b" & DQ,
               "cmd groups with double quotes");
            Assert
              (Hostkit.Shell.Quote ("say " & DQ & "hi" & DQ)
                 = DQ & "say " & DQ & DQ & "hi" & DQ & DQ & DQ,
               "an embedded double quote is doubled for cmd");
         end;
      else
         Assert (Hostkit.Shell.Command_Option = "-c", "sh is introduced with -c");
         Assert (Hostkit.Shell.Quote ("a b") = "'a b'", "sh groups with single quotes");
         Assert
           (Hostkit.Shell.Quote ("it's") = "'it'\''s'",
            "an embedded single quote is spliced for sh");
      end if;
   end Test_Quoting;

   procedure Test_Run_Reports_Exit_Status (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty  : Hostkit.String_Vectors.Vector;
      Status : Integer := -1;
      Ran    : Boolean;
   begin
      Ran := Hostkit.Process.Run (Companion ("noop"), Empty, Status);
      Assert (Ran, "a program that succeeds is reported as having run");
      Assert (Status = 0, "and its exit status is zero; was " & Status'Image);

      Ran := Hostkit.Process.Run (Companion ("failing"), Empty, Status);
      Assert (not Ran, "a program that fails is not reported as successful");
      Assert (Status = 7, "and its own exit status is reported; was " & Status'Image);
   end Test_Run_Reports_Exit_Status;

   procedure Test_Launch_Does_Not_Wait (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty : Hostkit.String_Vectors.Vector;
   begin
      --  A detached launch says only that it began. It has no exit status to give, and
      --  reporting one -- as the backgrounding shell's zero used to be reported -- says
      --  nothing whatever about the program.
      Assert (Hostkit.Process.Launch (Companion ("noop"), Empty), "a launch that starts says so");
      Assert
        (not Hostkit.Process.Launch ("", Empty),
         "a launch with no program to run does not claim to have started");
   end Test_Launch_Does_Not_Wait;

   procedure Test_Shell_Quoting_Holds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Arguments : Hostkit.String_Vectors.Vector;
      Status    : Integer := -1;
      Ran       : Boolean;

      --  An argument that tries to be a second command. If the quoting holds it stays
      --  one argument to Noop, which ignores it and exits zero; if it leaks, the shell
      --  runs "exit 9" and the status says so.
      Separator : constant String := (if Hostkit.Shell.Is_Command_Shell then "&" else ";");
   begin
      Arguments.Append (To_Unbounded_String ("literal" & Separator & " exit 9"));

      Ran :=
        Hostkit.Process.Run_Shell_Command
          (Hostkit.Shell.Command_Line (Companion ("noop"), Arguments),
           Wait        => True,
           Exit_Status => Status);

      Assert (Ran, "the quoted command runs to completion when awaited");
      Assert
        (Status = 0,
         "the separator stays inside one argument rather than running as a command; exit was "
         & Status'Image);
   end Test_Shell_Quoting_Holds;

   procedure Test_Captured_Run (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Ada.Strings.Unbounded;

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
   end Test_Captured_Run;

   procedure Test_Timeout_Kills (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Ada.Strings.Unbounded;

      Arguments : Hostkit.String_Vectors.Vector;
      Outcome   : Hostkit.Process.Process_Outcome;
   begin
      --  A program that will not stop. Without a deadline the caller waits for ever, which
      --  is the whole reason Run_Captured takes one.
      Arguments.Append (To_Unbounded_String ("--hang"));

      Outcome :=
        Hostkit.Process.Run_Captured
          (Program    => Companion ("sleeper"),
           Arguments  => Arguments,
           Timeout_Ms => 300);

      Assert (Outcome.Started, "the program started");
      Assert (Outcome.Timed_Out, "and the deadline ended it, rather than the program");
   end Test_Timeout_Kills;

   procedure Test_Accessible_By_Others (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Ada.Strings.Unbounded;

      procedure Write (Path : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put_Line (File, "key");
         Ada.Text_IO.Close (File);
      end Write;

      Secure : constant String := Ada.Directories.Compose (Scratch, "hk-key-0600");
      Open   : constant String := Ada.Directories.Compose (Scratch, "hk-key-0644");

      function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "chmod";

      procedure Chmod (Path : String; Mode : Interfaces.C.int) is
         C_Path  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
         Ignored : constant Interfaces.C.int := C_Chmod (C_Path, Mode);
      begin
         pragma Unreferenced (Ignored);
         Interfaces.C.Strings.Free (C_Path);
      end Chmod;
   begin
      --  Only meaningful where mode bits mean something; on Windows this always answers False,
      --  and setting a POSIX mode there is a no-op, so there is nothing to assert.
      if not Hostkit.Shell.Is_Command_Shell then
         Write (Secure);
         Write (Open);
         Chmod (Secure, 8#600#);
         Chmod (Open, 8#644#);

         Assert
           (not Hostkit.Fs.Accessible_By_Others (Secure),
            "a 0600 file is not accessible by others");
         Assert
           (Hostkit.Fs.Accessible_By_Others (Open),
            "a 0644 file is accessible by others");
      end if;

      Assert
        (not Hostkit.Fs.Accessible_By_Others (Ada.Directories.Current_Directory),
         "a directory is not judged by this -- regular files only");
   end Test_Accessible_By_Others;

   procedure Test_A_Directory_Is_Not_Executable (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  GNAT.OS_Lib.Is_Executable_File says True here on Windows, and an open action
      --  pointing at a directory was duly launched.
      Assert
        (not Hostkit.Fs.Is_Executable (Ada.Directories.Current_Directory),
         "a directory is not something this host runs");
      Assert
        (Hostkit.Fs.Is_Executable (Companion ("noop")),
         "and a program that this host runs, is");
   end Test_A_Directory_Is_Not_Executable;

   type Hostkit_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Hostkit_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Hostkit_Test_Case);

   overriding function Name (T : Hostkit_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("hostkit");
   end Name;

   overriding procedure Register_Tests (T : in out Hostkit_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Quoting'Access, "shell : the quoting matches the shell it quotes for");
      Register_Routine
        (T, Test_Run_Reports_Exit_Status'Access, "process : Run reports the program's own exit status");
      Register_Routine
        (T, Test_Launch_Does_Not_Wait'Access, "process : Launch starts and does not wait");
      Register_Routine
        (T, Test_Shell_Quoting_Holds'Access, "shell : an argument cannot become a second command");
      Register_Routine
        (T, Test_A_Directory_Is_Not_Executable'Access, "fs : a directory is not executable");
      Register_Routine
        (T, Test_Accessible_By_Others'Access, "fs : a group- or world-readable file is flagged");
      Register_Routine
        (T, Test_Captured_Run'Access, "process : a captured run keeps stdout and stderr apart");
      Register_Routine
        (T, Test_Timeout_Kills'Access, "process : a program that will not stop is stopped");
   end Register_Tests;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      pragma Warnings (Off, "use of an anonymous access type allocator");
      Result.Add_Test (new Hostkit_Test_Case);
      pragma Warnings (On, "use of an anonymous access type allocator");
      return Result;
   end Suite;

end Hostkit_Suite;
