with AUnit.Assertions;
with AUnit;
with AUnit.Test_Cases;

with Ada.Calendar;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces.C.Strings;
with Ada.Strings.Unbounded;

with Hostkit;
with Hostkit.Filesystem_Rules;
with Hostkit.Fs;
with Hostkit.Host;
with Hostkit.Metadata;
with Hostkit.Process;
with Hostkit.Shell;
with Hostkit.Watch;
with Hostkit.Windows_Command_Line;

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

   --  The first line of a file, with nothing either side of it.
   function First_Line (Path : String) return String is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      if Ada.Text_IO.End_Of_File (File) then
         Ada.Text_IO.Close (File);
         return "";
      end if;

      declare
         Line : constant String := Ada.Text_IO.Get_Line (File);
      begin
         Ada.Text_IO.Close (File);
         return Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both);
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return "";
   end First_Line;

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

   procedure Test_Windows_Command_Line_Quoting
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      package WCL renames Hostkit.Windows_Command_Line;

      --  Spelt from these rather than as a literal thicket of doubled quotes and
      --  backslashes, for the same reason the shell test above does: the thicket
      --  is where a wrong expectation hides. DQ is one double quote, BS is one
      --  backslash.
      DQ : constant String := """";
      BS : constant String := "\";

      Args : Hostkit.String_Vectors.Vector;
   begin
      --  The CRT quoting is pure text, so it is checked on every host, not only
      --  on the Windows one that hands the result to CreateProcessW.
      Assert
        (WCL.Quote_Argument ("simple") = "simple",
         "an argument with nothing special is left alone");
      Assert
        (WCL.Quote_Argument ("a" & BS & "b") = "a" & BS & "b",
         "a backslash that is not next to a quote or a space needs no quoting");
      Assert
        (WCL.Quote_Argument ("a b") = DQ & "a b" & DQ,
         "an argument with a space is wrapped in quotes");
      Assert
        (WCL.Quote_Argument ("") = DQ & DQ,
         "an empty argument is an explicit pair of quotes, not nothing");

      --  The headline bug: a directory path with a space and a trailing backslash.
      --  Naively wrapped it is "C:\Program Files\", whose trailing backslash
      --  escapes the closing quote; the run before the quote must be doubled.
      Assert
        (WCL.Quote_Argument ("C:" & BS & "Program Files" & BS)
           = DQ & "C:" & BS & "Program Files" & BS & BS & DQ,
         "backslashes running up to the closing quote are doubled");

      Assert
        (WCL.Quote_Argument ("say " & DQ & "hi" & DQ)
           = DQ & "say " & BS & DQ & "hi" & BS & DQ & DQ,
         "an embedded quote is escaped with a backslash");
      Assert
        (WCL.Quote_Argument ("a" & BS & DQ)
           = DQ & "a" & BS & BS & BS & DQ & DQ,
         "backslashes before an embedded quote are doubled, then the quote escaped");

      Args.Append (To_Unbounded_String ("a b"));
      Args.Append (To_Unbounded_String ("plain"));
      Assert
        (WCL.Build ("prog", Args) = "prog " & DQ & "a b" & DQ & " plain",
         "the command line is the program and its arguments quoted and space-joined");
      Assert
        (WCL.Build ("my prog", Hostkit.String_Vectors.Empty_Vector)
           = DQ & "my prog" & DQ,
         "a program whose path has a space is quoted too");
   end Test_Windows_Command_Line_Quoting;

   procedure Test_Filesystem_Rules (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      package FR renames Hostkit.Filesystem_Rules;

      LF     : constant Character := Character'Val (10);
      --  A miniature /proc/self/mountinfo: an ext4 root, a FAT stick under
      --  /media/usb, and an ext4 disk under /media/usb-backup whose mount point
      --  merely starts with the same text.
      Sample : constant String :=
        "30 1 8:2 / / rw,relatime - ext4 /dev/sda2 rw" & LF
        & "48 30 8:17 / /media/usb rw,nosuid - vfat /dev/sdb1 rw,fmask=0022" & LF
        & "49 30 8:33 / /media/usb-backup rw - ext4 /dev/sdc1 rw";
   begin
      --  The type classification is pure and matched case-insensitively.
      Assert (FR.Dos_By_Type_Name ("vfat"), "vfat is a DOS-ruled filesystem");
      Assert (FR.Dos_By_Type_Name ("exfat") and then FR.Dos_By_Type_Name ("ntfs"),
              "exfat and ntfs are DOS-ruled");
      Assert (FR.Dos_By_Type_Name ("FAT32") and then FR.Dos_By_Type_Name ("NTFS"),
              "the classifier is case-insensitive");
      Assert (not FR.Dos_By_Type_Name ("ext4"), "ext4 is not DOS-ruled");
      Assert (not FR.Dos_By_Type_Name ("apfs") and then not FR.Dos_By_Type_Name ("btrfs"),
              "apfs and btrfs are not DOS-ruled");
      Assert (not FR.Dos_By_Type_Name (""), "an unknown filesystem is not DOS-ruled");

      --  The deepest covering mount wins, and a sibling that merely shares a
      --  prefix (/media/usb-backup vs /media/usb) does not match.
      Assert
        (FR.Filesystem_Type_For_Mount (Sample, "/home/user/doc.txt") = "ext4",
         "a path under the root mount reports the root filesystem");
      Assert
        (FR.Filesystem_Type_For_Mount (Sample, "/media/usb/photo.png") = "vfat",
         "a path under a deeper mount reports that mount's filesystem");
      Assert
        (FR.Filesystem_Type_For_Mount (Sample, "/media/usb-backup/x") = "ext4",
         "a sibling mount sharing a name prefix is not matched");
      Assert
        (FR.Dos_By_Type_Name (FR.Filesystem_Type_For_Mount (Sample, "/media/usb/x")),
         "a file destined for the FAT stick is judged DOS-ruled");

      --  The host query answers, and agrees with the host: a POSIX scratch
      --  directory is not DOS-ruled, while every Windows volume is.
      if Hostkit.Shell.Is_Command_Shell then
         Assert (Hostkit.Fs.Uses_Dos_Filename_Rules (Scratch),
                 "Windows treats its volumes as DOS-ruled");
      else
         Assert (not Hostkit.Fs.Uses_Dos_Filename_Rules (Scratch),
                 "a POSIX scratch directory is not DOS-ruled");
      end if;
      Assert
        (not Hostkit.Fs.Uses_Dos_Filename_Rules ("") or else Hostkit.Shell.Is_Command_Shell,
         "an unresolvable path answers without raising");
   end Test_Filesystem_Rules;

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

   procedure Test_Elevation_Is_Asked_Not_Assumed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Hostkit.Host.Kind;

      Elevated : constant Boolean := Hostkit.Host.Is_Elevated;
   begin
      if Hostkit.Host.Current = Hostkit.Host.Windows then
         --  There is no cheap second opinion here: every way of asking Windows
         --  whether this token is elevated goes through the same call. The
         --  POSIX branch below is the one carrying the cross-check.
         Assert
           (Elevated or else not Elevated,
            "the elevation query answers rather than raising");
         return;
      end if;

      --  A second route to the same fact: geteuid(2) through the library, and
      --  id(1) through a program. An answer only one of them gives is an answer
      --  about our own code rather than about the host.
      declare
         Id        : constant String := Hostkit.Process.Locate ("id");
         Out_Path  : constant String :=
           Ada.Directories.Compose (Scratch, "hk-elevation.txt");
         Arguments : Hostkit.String_Vectors.Vector;
         Outcome   : Hostkit.Process.Process_Outcome;
      begin
         if Id = "" then
            return;
         end if;

         Arguments.Append (To_Unbounded_String ("-u"));
         Outcome :=
           Hostkit.Process.Run_Captured
             (Program     => Id,
              Arguments   => Arguments,
              Stdout_Path => Out_Path,
              Timeout_Ms  => 20_000);

         Assert (Outcome.Started and then Outcome.Exit_Status = 0, "id -u ran");

         --  The whole line, not a search for "0": every other user id on this
         --  host contains one somewhere.
         declare
            Reported : constant String := First_Line (Out_Path);
         begin
            Assert
              ((Reported = "0") = Elevated,
               "the library and id(1) agree about who this process is; id said "
               & Reported);
         end;
      end;
   end Test_Elevation_Is_Asked_Not_Assumed;

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

   --  Write a file with something in it, as a fixture.
   procedure Write_File (Path : String; Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Text);
      Ada.Text_IO.Close (File);
   end Write_File;

   procedure Test_Metadata_Reports_What_It_Could_Not_Get
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Missing   : constant String := Ada.Directories.Compose (Scratch, "hk-no-such-file-xyzzy");
      Mode      : Natural;
      Available : Boolean;
      User_Id   : Natural;
      Group_Id  : Natural;
      Born      : Ada.Calendar.Time;
      pragma Unreferenced (Born);
   begin
      --  The contract that keeps a caller from inventing facts: a path this host
      --  cannot answer for reports Available => False, and the value that comes
      --  back with it is not a fact about any file.
      Mode := Hostkit.Metadata.File_Permission_Bits (Missing, Available);
      Assert (not Available, "a missing file has no permission bits to report");
      Assert (Mode = 0, "and the accompanying value is the neutral 0, not a mode");

      Hostkit.Metadata.File_Ownership (Missing, User_Id, Group_Id, Available);
      Assert (not Available, "a missing file has no ownership to report");

      Born := Hostkit.Metadata.File_Creation_Time (Missing, Available);
      Assert (not Available, "a missing file has no creation time to report");

      Assert
        (not Hostkit.Metadata.Volume_Capacity_Of (Missing & "/deeper").Available
           or else True,
         "asking about a volume that is not there does not raise");
   end Test_Metadata_Reports_What_It_Could_Not_Get;

   procedure Test_Mode_And_Ownership_Agree_With_The_Separate_Calls
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant String := Ada.Directories.Compose (Scratch, "hk-meta-modes");

      Separate_Mode      : Natural;
      Separate_Mode_Ok   : Boolean;
      Separate_User      : Natural;
      Separate_Group     : Natural;
      Separate_Owner_Ok  : Boolean;

      Joint_Mode         : Natural;
      Joint_Mode_Ok      : Boolean;
      Joint_User         : Natural;
      Joint_Group        : Natural;
      Joint_Owner_Ok     : Boolean;
   begin
      Write_File (Path, "x");

      --  File_Mode_And_Ownership exists only to save a syscall. If it ever
      --  disagreed with the two calls it stands in for, it would be a silent
      --  wrong answer in the middle of a directory listing -- so this is the
      --  assertion that earns it.
      Separate_Mode := Hostkit.Metadata.File_Permission_Bits (Path, Separate_Mode_Ok);
      Hostkit.Metadata.File_Ownership (Path, Separate_User, Separate_Group, Separate_Owner_Ok);

      Hostkit.Metadata.File_Mode_And_Ownership
        (Path, Joint_Mode, Joint_Mode_Ok, Joint_User, Joint_Group, Joint_Owner_Ok);

      Assert (Joint_Mode_Ok = Separate_Mode_Ok, "both report mode availability the same way");
      Assert (Joint_Owner_Ok = Separate_Owner_Ok, "both report ownership availability the same way");

      if Separate_Mode_Ok then
         Assert (Joint_Mode = Separate_Mode, "the joint call reports the same mode bits");
      end if;

      if Separate_Owner_Ok then
         Assert (Joint_User = Separate_User, "the joint call reports the same owner");
         Assert (Joint_Group = Separate_Group, "the joint call reports the same group");
      end if;

      --  And a mode this host can set is a mode it reads back.
      if Hostkit.Metadata.Permissions_Supported then
         Assert (Hostkit.Metadata.Set_Permissions (Path, 8#640#), "the host sets a mode it supports");
         Separate_Mode := Hostkit.Metadata.File_Permission_Bits (Path, Separate_Mode_Ok);
         Assert
           (Separate_Mode_Ok and then Separate_Mode = 8#640#,
            "and reads back exactly the mode it was given");
      end if;

      Ada.Directories.Delete_File (Path);
   end Test_Mode_And_Ownership_Agree_With_The_Separate_Calls;

   procedure Test_Same_File_Sees_Through_A_Second_Name
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Original : constant String := Ada.Directories.Compose (Scratch, "hk-same-original");
      Twin     : constant String := Ada.Directories.Compose (Scratch, "hk-same-twin");
      Other    : constant String := Ada.Directories.Compose (Scratch, "hk-same-other");

      procedure Remove (Path : String) is
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Remove;
   begin
      Remove (Original);
      Remove (Twin);
      Remove (Other);

      Write_File (Original, "content");
      Write_File (Other, "content");

      Assert (Hostkit.Metadata.Same_File (Original, Original), "a file is the same file as itself");
      Assert
        (not Hostkit.Metadata.Same_File (Original, Other),
         "two files with identical contents are still two files");
      Assert
        (not Hostkit.Metadata.Same_File (Original, Ada.Directories.Compose (Scratch, "hk-same-absent")),
         "a path that does not exist is not the same file as one that does");

      --  A hard link is the identity a case-insensitive host gives two spellings
      --  of one name: two paths, one file. It is the case this exists to catch,
      --  and the one that destroys data when answered wrongly.
      if Hostkit.Fs.Create_Hard_Link (Original, Twin) then
         Assert
           (Hostkit.Metadata.Same_File (Original, Twin),
            "two names for one file are the same file");
         Ada.Directories.Delete_File (Twin);
      end if;

      Ada.Directories.Delete_File (Original);
      Ada.Directories.Delete_File (Other);
   end Test_Same_File_Sees_Through_A_Second_Name;

   procedure Test_A_Name_Round_Trips_Through_Its_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path      : constant String := Ada.Directories.Compose (Scratch, "hk-meta-owner");
      User_Id   : Natural;
      Group_Id  : Natural;
      Available : Boolean;
   begin
      if not Hostkit.Metadata.Ownership_Supported then
         --  Windows has no uid/gid pair; the host says so once, here, rather than
         --  every one of these answering with a plausible 0.
         Assert
           (Hostkit.Metadata.User_Name_For_Id (0) = "",
            "a host without ownership resolves no names");
         return;
      end if;

      Write_File (Path, "x");
      Hostkit.Metadata.File_Ownership (Path, User_Id, Group_Id, Available);
      Assert (Available, "a file this process just created has ownership to report");

      declare
         Name  : constant String := Hostkit.Metadata.User_Name_For_Id (User_Id);
         Found : Boolean;
         Back  : Natural;
      begin
         Assert (Name /= "", "the owning user id resolves to a name");
         Back := Hostkit.Metadata.User_Id_For_Name (Name, Found);
         Assert (Found, "and that name resolves back to an id");
         Assert (Back = User_Id, "which is the id it came from");
      end;

      declare
         Name  : constant String := Hostkit.Metadata.Group_Name_For_Id (Group_Id);
         Found : Boolean;
         Back  : Natural;
      begin
         if Name /= "" then
            Back := Hostkit.Metadata.Group_Id_For_Name (Name, Found);
            Assert (Found, "the owning group name resolves back to an id");
            Assert (Back = Group_Id, "which is the id it came from");
         end if;
      end;

      Ada.Directories.Delete_File (Path);
   end Test_A_Name_Round_Trips_Through_Its_Id;

   procedure Test_A_Volume_Has_Room (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Capacity : constant Hostkit.Metadata.Volume_Capacity :=
        Hostkit.Metadata.Volume_Capacity_Of (Ada.Directories.Current_Directory);
   begin
      Assert (Capacity.Available, "the volume this test is running on reports its capacity");
      Assert (Capacity.Capacity_Bytes > 0, "a mounted volume has a size");
      Assert
        (Capacity.Free_Bytes <= Capacity.Capacity_Bytes,
         "free space cannot exceed the volume it is free on");
      Assert
        (not Capacity.Inodes_Known or else Capacity.Free_Inode_Count <= Capacity.Inode_Count,
         "free inodes cannot exceed the inodes there are");
   end Test_A_Volume_Has_Room;

   --  Notification is asynchronous on every host, so a change is waited for
   --  rather than expected on the first poll -- up to five seconds, which is far
   --  beyond any plausible delivery and still bounded.
   Settle : constant Duration := 0.05;
   Rounds : constant Natural := 100;

   function Wait_For_Change (State : in out Hostkit.Watch.Watch_State) return Boolean is
   begin
      for Unused_Round in 1 .. Rounds loop
         if Hostkit.Watch.Poll (State) then
            return True;
         end if;

         delay Settle;
      end loop;

      return False;
   end Wait_For_Change;

   --  Swallow the events the fixture's own setup produced, so the assertions
   --  that follow are about the change the test made.
   procedure Drain (State : in out Hostkit.Watch.Watch_State) is
      Ignored : Boolean;
   begin
      delay Settle;
      Ignored := Hostkit.Watch.Poll (State);
      pragma Unreferenced (Ignored);
   end Drain;

   procedure Touch (Directory : String; Name : String) is
      Output : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create
        (Output, Ada.Text_IO.Out_File, Ada.Directories.Compose (Directory, Name));
      Ada.Text_IO.Put_Line (Output, "x");
      Ada.Text_IO.Close (Output);
   end Touch;

   procedure Test_A_Fresh_Watch_Is_Inactive (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State : Hostkit.Watch.Watch_State;
   begin
      Assert (not Hostkit.Watch.Is_Active (State), "a fresh watch is inactive");
      Assert (not Hostkit.Watch.Poll (State), "polling an inactive watch reports no change");
   end Test_A_Fresh_Watch_Is_Inactive;

   procedure Test_An_Unwatchable_Path_Fails_Quietly (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State : Hostkit.Watch.Watch_State;
   begin
      --  A watch that cannot be established leaves the caller to its polling
      --  timer rather than raising: the listing still refreshes, less promptly.
      Hostkit.Watch.Watch_Path (State, Ada.Directories.Compose (Scratch, "no-such-directory-xyzzy"));
      Assert (not Hostkit.Watch.Is_Active (State), "an unwatchable path does not activate");
      Assert (not Hostkit.Watch.Poll (State), "a watch that failed simply reports no change");

      Hostkit.Watch.Watch_Path (State, "");
      Assert (not Hostkit.Watch.Is_Active (State), "an empty path does not activate");
   end Test_An_Unwatchable_Path_Fails_Quietly;

   procedure Test_The_Watch_Notices_Changes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Directory : constant String := Ada.Directories.Compose (Scratch, "hostkit_watch_test_dir");
      State     : Hostkit.Watch.Watch_State;
   begin
      if Ada.Directories.Exists (Directory) then
         Ada.Directories.Delete_Tree (Directory);
      end if;

      Ada.Directories.Create_Directory (Directory);

      Hostkit.Watch.Watch_Path (State, Directory);
      Assert (Hostkit.Watch.Is_Active (State), "watching a real directory activates the native watch");

      Drain (State);
      Assert (not Hostkit.Watch.Poll (State), "a directory nobody touched reports no change");

      Touch (Directory, "created.txt");
      Assert (Wait_For_Change (State), "creating a file is noticed");
      Assert (not Hostkit.Watch.Poll (State), "the change is consumed, not reported twice");

      Ada.Directories.Delete_File (Ada.Directories.Compose (Directory, "created.txt"));
      Assert (Wait_For_Change (State), "deleting a file is noticed");

      Assert (Hostkit.Watch.Event_Count (State) > 0, "events are counted");

      Hostkit.Watch.Release (State);
      Assert (not Hostkit.Watch.Is_Active (State), "release deactivates the watch");

      Ada.Directories.Delete_Tree (Directory);
   end Test_The_Watch_Notices_Changes;

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
        (T, Test_Windows_Command_Line_Quoting'Access,
         "process : the Windows CRT argument quoting round-trips");
      Register_Routine
        (T, Test_Filesystem_Rules'Access,
         "fs : DOS-ruled filesystems are recognised from the mount table");
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
        (T, Test_Elevation_Is_Asked_Not_Assumed'Access,
         "host : elevation is asked of the host, not assumed");
      Register_Routine
        (T, Test_Captured_Run'Access, "process : a captured run keeps stdout and stderr apart");
      Register_Routine
        (T, Test_Captured_Input'Access, "process : a captured run reads the file it was given");
      Register_Routine
        (T, Test_Timeout_Kills'Access, "process : a program that will not stop is stopped");
      Register_Routine
        (T, Test_Metadata_Reports_What_It_Could_Not_Get'Access,
         "metadata : what the host could not answer is reported, not invented");
      Register_Routine
        (T, Test_Mode_And_Ownership_Agree_With_The_Separate_Calls'Access,
         "metadata : the one-call mode+ownership read agrees with the two it replaces");
      Register_Routine
        (T, Test_Same_File_Sees_Through_A_Second_Name'Access,
         "metadata : two names for one file are recognised as the same file");
      Register_Routine
        (T, Test_A_Name_Round_Trips_Through_Its_Id'Access,
         "metadata : an owner name round-trips through its numeric id");
      Register_Routine
        (T, Test_A_Volume_Has_Room'Access, "metadata : a mounted volume reports its capacity");
      Register_Routine
        (T, Test_A_Fresh_Watch_Is_Inactive'Access, "watch : a fresh watch is inactive");
      Register_Routine
        (T, Test_An_Unwatchable_Path_Fails_Quietly'Access,
         "watch : a directory that cannot be watched fails quietly");
      Register_Routine
        (T, Test_The_Watch_Notices_Changes'Access,
         "watch : the host's notification facility notices creations and deletions");
   end Register_Tests;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Hostkit_Test_Case));
      return Result;
   end Suite;

end Hostkit_Suite;
