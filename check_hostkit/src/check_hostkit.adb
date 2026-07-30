with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Text;
with Project_Tools.Tree_Checks;

procedure Check_Hostkit is
   use Ada.Text_IO;

   Build_Command : constant String := "alr --non-interactive build";
   GNAT_Version_Check_Command : constant String := "alr exec -- gnatls --version";
   Tests_Run_Command : constant String := "./bin/hostkit_tests";

   function Root_Directory return String is
      Current : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Current & "/hostkit.gpr") then
         return Current;
      elsif Ada.Directories.Exists (Current & "/../hostkit.gpr") then
         return Ada.Directories.Full_Name (Current & "/..");
      else
         Put_Line (Standard_Error, "hostkit root not found from " & Current);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Root_Directory;

   Root   : constant String := Root_Directory;
   Errors : Natural := 0;

   procedure Error (Message : String) is
   begin
      Errors := Errors + 1;
      Put_Line (Standard_Error, "error: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Error;

   procedure Require_Alire_GNAT_15 is
      Output : constant String :=
        Project_Tools.Processes.Shell_Output
          ("cd " & Project_Tools.Processes.Shell_Quote (Root) & " && " & GNAT_Version_Check_Command);
   begin
      Put_Line ("");
      Put_Line ("==> verify Alire-selected GNAT 15 toolchain");

      if Output = "" then
         Error ("alr exec -- gnatls --version failed");
      elsif Project_Tools.Text.Contains (Output, "GNATLS 15.") = False then
         Error ("hostkit must build with Alire-selected GNAT 15, got: " & Output);
      end if;
   end Require_Alire_GNAT_15;

   procedure Require_Text (Relative_Path : String; Pattern : String; Message : String) is
   begin
      Project_Tools.Files.Require_Contains (Root & "/" & Relative_Path, Pattern, Message);
   end Require_Text;

   procedure Require_GNAT_15_Manifest (Relative_Path : String) is
   begin
      Require_Text
        (Relative_Path,
         "gnat_native = ""=15.2.1""",
         Relative_Path & " must pin gnat_native = ""=15.2.1""");
   end Require_GNAT_15_Manifest;

   procedure Run_Command (Label : String; Dir : String; Command : String) is
      Status : Integer;
   begin
      Put_Line ("");
      Put_Line ("==> " & Label);

      Status := Project_Tools.Processes.Run_Shell_In_Directory (Dir, Command);
      if Status /= 0 then
         Error (Label & " failed with status" & Integer'Image (Status));
      end if;
   end Run_Command;

   --  Every per-OS body must actually bind its host's API.
   --
   --  A body that has quietly become a stub still compiles, still passes the
   --  Linux suite, and answers exactly the "not available" that a genuinely
   --  absent facility answers -- so nothing catches it except naming the import
   --  that has to be there. These are the calls this crate exists to make; if
   --  one is removed, that is a decision to take deliberately and to change here.
   procedure Require_Binding (Relative_Path : String; Host_Call : String) is
   begin
      --  Match the import itself, not merely the name somewhere in the file.
      --  The first version of this looked for the quoted name alone and was
      --  satisfied by the diagnostic string in Current -- so renaming the actual
      --  External_Name passed the check. A guardrail that cannot fail is worse
      --  than none, because it reads as coverage.
      Require_Text
        (Relative_Path,
         "External_Name => """ & Host_Call & """",
         Relative_Path & " must bind " & Host_Call);
   end Require_Binding;

   --  A unit with per-OS bodies needs one for every host, or the build for the
   --  missing host fails -- and it fails on that host's runner, not here.
   procedure Require_A_Body_Per_Host is
      Hosts  : constant array (1 .. 3) of Unbounded_String :=
        [To_Unbounded_String ("macos"),
         To_Unbounded_String ("windows"),
         To_Unbounded_String ("unsupported")];
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Start_Search
        (Search, Root & "/src/platform/linux", "*.adb");

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);

         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            for Host of Hosts loop
               if not Ada.Directories.Exists
                        (Root & "/src/platform/" & To_String (Host) & "/" & Name)
               then
                  Error
                    (Name & " has a Linux body but none for "
                     & To_String (Host) & "; every host needs one");
               end if;
            end loop;
         end;
      end loop;

      Ada.Directories.End_Search (Search);
   end Require_A_Body_Per_Host;

   procedure Check_Generated_Artifacts is
      Hygiene_Errors : Natural := 0;
   begin
      Project_Tools.Tree_Checks.Check_No_Generated_Python (Hygiene_Errors, Root & "/src");
      Project_Tools.Tree_Checks.Check_No_Generated_Python (Hygiene_Errors, Root & "/tests/src");
      Errors := Errors + Hygiene_Errors;
   end Check_Generated_Artifacts;

begin
   Project_Tools.Processes.Require_Command ("alr", "alr executable not found on PATH");
   Require_Alire_GNAT_15;

   --  The published crate must not carry sibling path pins.
   Project_Tools.Alire_Manifests.Require_Pin_Free_Crate_Manifest
     (Root & "/alire.toml", "hostkit");
   Require_GNAT_15_Manifest ("alire.toml");
   Require_GNAT_15_Manifest ("tests/alire.toml");
   Require_GNAT_15_Manifest ("tools/alire.toml");
   Require_GNAT_15_Manifest ("check_hostkit/alire.toml");

   Project_Tools.Files.Require_Files
     ([To_Unbounded_String (Root & "/README.md"),
       To_Unbounded_String (Root & "/CLAUDE.md"),
       To_Unbounded_String (Root & "/AGENTS.md"),
       To_Unbounded_String (Root & "/hostkit.gpr"),
       To_Unbounded_String (Root & "/src/hostkit.ads"),
       To_Unbounded_String (Root & "/tests/alire.toml"),
       To_Unbounded_String (Root & "/tests/hostkit_tests.gpr")],
      "required hostkit release file missing");

   --  The on-ramp docs must actually carry the crate's contract and how to work it.
   Require_Text
     ("README.md", "alr build",
      "README must document the build command");
   Require_Text
     ("README.md", "hostkit_tests",
      "README must document how to run the test suite");
   Require_Text
     ("README.md", "because the host differs",
      "README must state the inclusion rule (does it differ because the host differs?)");
   Require_Text
     ("README.md", "not optional",
      "README must document that tri-platform CI is mandatory");
   Require_Text
     ("AGENTS.md", "because the host differs",
      "AGENTS.md must carry the inclusion rule for agents");
   Require_Text
     ("AGENTS.md", "Cannot tell",
      "AGENTS.md must carry the ""cannot tell is not fine"" contract");

   Require_A_Body_Per_Host;

   --  The host calls, per body. Grouped by what they are for rather than by
   --  host, because the point of each row is that the same question is answered
   --  by a different call on each one.
   --
   --  Directory-change notification.
   Require_Binding ("src/platform/linux/hostkit-watch.adb", "inotify_init1");
   Require_Binding ("src/platform/linux/hostkit-watch.adb", "inotify_add_watch");
   Require_Binding ("src/platform/macos/hostkit-watch.adb", "kqueue");
   Require_Binding ("src/platform/macos/hostkit-watch.adb", "kevent");
   Require_Binding ("src/platform/windows/hostkit-watch.adb", "FindFirstChangeNotificationA");

   --  File metadata: what the filesystem says about a file.
   Require_Binding ("src/platform/linux/hostkit-metadata.adb", "statx");
   Require_Binding ("src/platform/linux/hostkit-metadata.adb", "statvfs");
   Require_Binding ("src/platform/macos/hostkit-metadata.adb", "statfs$INODE64");
   Require_Binding ("src/platform/windows/hostkit-metadata.adb", "GetDiskFreeSpaceExA");
   Require_Binding ("src/platform/windows/hostkit-metadata.adb", "GetFileAttributesExA");

   --  Ownership. The Windows pair is what makes Metadata.Set_Ownership a
   --  different operation from Fs.Set_Owner, so losing it is losing a feature
   --  rather than losing a duplicate -- which is exactly what happened once.
   Require_Binding ("src/platform/linux/hostkit-metadata.adb", "chown");
   Require_Binding ("src/platform/macos/hostkit-metadata.adb", "chown");
   Require_Binding ("src/platform/windows/hostkit-metadata.adb", "GetNamedSecurityInfoA");
   Require_Binding ("src/platform/windows/hostkit-metadata.adb", "SetNamedSecurityInfoA");

   --  The host's own trash. Linux deliberately binds nothing: the freedesktop
   --  trash is a filesystem layout for the caller to write, not a call to make.
   Require_Binding ("src/platform/windows/hostkit-trash.adb", "SHFileOperationW");
   Require_Binding ("src/platform/macos/hostkit-trash.adb", "FSMoveObjectToTrashSync");

   --  The host's locale. POSIX has none, and answers "" on purpose.
   Require_Binding ("src/platform/windows/hostkit-host.adb", "GetUserDefaultLocaleName");
   Require_Binding ("src/platform/macos/hostkit-host.adb", "CFLocaleCopyCurrent");

   --  Reading a link's own target, which Windows has no readlink for.
   Require_Binding ("src/platform/linux/hostkit-fs.adb", "readlink");
   Require_Binding ("src/platform/windows/hostkit-fs.adb", "DeviceIoControl");

   Check_Generated_Artifacts;

   Run_Command ("build hostkit library", Root, Build_Command);
   Run_Command ("build hostkit tests", Root & "/tests", Build_Command);
   Run_Command ("run hostkit tests", Root & "/tests", Tests_Run_Command);

   if Errors = 0 then
      Put_Line ("hostkit release check passed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line
        (Standard_Error,
         "hostkit release check failed:" & Natural'Image (Errors) & " error(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Program_Error =>
      null;
end Check_Hostkit;
