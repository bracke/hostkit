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
with Hostkit.Host;
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

   --  Setting a mode is the fixture here, not the thing under test, so it goes straight
   --  to chmod(2) rather than through Hostkit.Fs.Make_Private, which is one of the
   --  things being tested. A no-op on Windows, where the callers guard for it anyway.
   procedure Chmod (Path : String; Mode : Interfaces.C.int) is
      function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "chmod";

      C_Path  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Ignored : constant Interfaces.C.int := C_Chmod (C_Path, Mode);
   begin
      pragma Unreferenced (Ignored);
      Interfaces.C.Strings.Free (C_Path);
   end Chmod;

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

   procedure Test_Directory_Accessible_By_Others
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Private_Dir : constant String := Ada.Directories.Compose (Scratch, "hk-dir-0700");
      Open_Dir    : constant String := Ada.Directories.Compose (Scratch, "hk-dir-0755");
      A_File      : constant String := Ada.Directories.Compose (Scratch, "hk-dir-file");

      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, A_File);
      Ada.Text_IO.Close (File);

      --  Only meaningful where mode bits mean something; on Windows this always answers
      --  False, and setting a POSIX mode there is a no-op, so there is nothing to assert.
      if not Hostkit.Shell.Is_Command_Shell then
         Ada.Directories.Create_Path (Private_Dir);
         Ada.Directories.Create_Path (Open_Dir);
         Chmod (Private_Dir, 8#700#);
         Chmod (Open_Dir, 8#755#);

         Assert
           (not Hostkit.Fs.Directory_Accessible_By_Others (Private_Dir),
            "a 0700 directory is not accessible by others");
         Assert
           (Hostkit.Fs.Directory_Accessible_By_Others (Open_Dir),
            "a 0755 directory is accessible by others");
      end if;

      Assert
        (not Hostkit.Fs.Directory_Accessible_By_Others (A_File),
         "a regular file is not judged by this -- directories only");
   end Test_Directory_Accessible_By_Others;

   procedure Test_Make_Private (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      A_File  : constant String := Ada.Directories.Compose (Scratch, "hk-make-private-file");
      A_Dir   : constant String := Ada.Directories.Compose (Scratch, "hk-make-private-dir");
      Missing : constant String := Ada.Directories.Compose (Scratch, "hk-make-private-gone");

      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, A_File);
      Ada.Text_IO.Close (File);
      Ada.Directories.Create_Path (A_Dir);
      Chmod (A_File, 8#644#);
      Chmod (A_Dir, 8#755#);

      if Hostkit.Shell.Is_Command_Shell then
         Assert
           (not Hostkit.Fs.Make_Private (A_File),
            "a host with no mode bits says it did not make the path private");
      else
         Assert (Hostkit.Fs.Make_Private (A_File), "a file is made private");
         Assert
           (not Hostkit.Fs.Accessible_By_Others (A_File),
            "a file made private is no longer accessible by others");

         Assert (Hostkit.Fs.Make_Private (A_Dir), "a directory is made private");
         Assert
           (not Hostkit.Fs.Directory_Accessible_By_Others (A_Dir),
            "a directory made private is no longer accessible by others");
         Assert
           (Ada.Directories.Exists (A_Dir),
            "a directory made private can still be entered by its owner");
      end if;

      Assert
        (not Hostkit.Fs.Make_Private (Missing),
         "a path that is not there is not reported as made private");
   end Test_Make_Private;

   procedure Test_Locate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      --  The host's own shell is the one program certain to be present, and
      --  Hostkit.Shell already knows where it is: locating its simple name has
      --  to find it again.
      Shell_Path : constant String := Hostkit.Shell.Executable;
      Simple     : constant String := Ada.Directories.Simple_Name (Shell_Path);
      Found      : constant String := Hostkit.Process.Locate (Simple);
   begin
      Assert (Found /= "", "the host's own shell is found by name");
      Assert
        (Ada.Directories.Simple_Name (Found) = Simple,
         "locating a name returns that program, not another");
      Assert
        (Hostkit.Process.Locate ("hostkit-definitely-not-a-program") = "",
         "a name the host has no program for answers empty");
      Assert
        (Hostkit.Process.Locate ("") = "",
         "an empty name answers empty rather than something");
   end Test_Locate;

   procedure Test_The_Host_Is_Not_Guessed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Hostkit.Host.Kind;
   begin
      --  Two per-OS bodies, written independently, must agree about which host this is.
      --  An environment-sniffing answer is what this exists to replace, so the check is
      --  that the identity matches a fact of the host itself rather than a variable.
      Assert
        ((Hostkit.Host.Current = Hostkit.Host.Windows) = Hostkit.Shell.Is_Command_Shell,
         "the host kind agrees with the shell the host runs");
   end Test_The_Host_Is_Not_Guessed;

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
        (T,
         Test_Directory_Accessible_By_Others'Access,
         "fs : a group- or world-readable directory is flagged");
      Register_Routine
        (T, Test_Make_Private'Access, "fs : a path is restricted to its owner");
      Register_Routine
        (T, Test_Locate'Access, "process : a program is found by name");
      Register_Routine
        (T, Test_The_Host_Is_Not_Guessed'Access, "host : the host identifies itself");
      Register_Routine
        (T, Test_Captured_Run'Access, "process : a captured run keeps stdout and stderr apart");
      Register_Routine
        (T, Test_Timeout_Kills'Access, "process : a program that will not stop is stopped");
   end Register_Tests;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Hostkit_Test_Case));
      return Result;
   end Suite;

end Hostkit_Suite;
