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
     ("CLAUDE.md", "because the host differs",
      "CLAUDE.md must carry the inclusion rule for agents");
   Require_Text
     ("CLAUDE.md", "Cannot tell",
      "CLAUDE.md must carry the ""cannot tell is not fine"" contract");

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
