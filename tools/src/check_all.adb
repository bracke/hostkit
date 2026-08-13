with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Text;
with Project_Tools.Tree_Checks;

procedure Check_All is
   use Ada.Text_IO;

   function Project_Root return String is
      Here : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Here & "/hostkit.gpr") then
         return Here;
      elsif Ada.Directories.Exists (Here & "/../hostkit.gpr") then
         return Ada.Directories.Full_Name (Here & "/..");
      else
         return Here;
      end if;
   end Project_Root;

   Root   : constant String := Project_Root;
   Alr    : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Checks : constant Project_Tools.Release_Checks.Checker :=
     Project_Tools.Release_Checks.Create (Root);

   procedure Require_Alire_GNAT_15 is
      Output : Ada.Strings.Unbounded.Unbounded_String;
      Status : Integer;
   begin
      Status :=
        Project_Tools.Processes.Run_Status
          ("verify Alire-selected GNAT 15 toolchain",
           Root,
           Alr,
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("exec"),
               Project_Tools.Processes.Argument ("--"),
               Project_Tools.Processes.Argument ("gnatls"),
               Project_Tools.Processes.Argument ("--version")]),
           Output,
           Quiet => False);

      if Status /= 0 then
         Put_Line (Standard_Error, "alr exec -- gnatls --version failed");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      elsif Project_Tools.Text.Contains (Ada.Strings.Unbounded.To_String (Output), "GNATLS 15.") = False then
         Put_Line
           (Standard_Error,
            "hostkit must build with Alire-selected GNAT 15, got: "
            & Ada.Strings.Unbounded.To_String (Output));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Require_Alire_GNAT_15;
begin
   if not Ada.Directories.Exists (Root & "/hostkit.gpr") then
      Put_Line (Standard_Error, "check_all must be run from the hostkit root or tools directory");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Project_Tools.Processes.Require_Command
     ("alr", "alr executable not found on PATH");
   Require_Alire_GNAT_15;

   Project_Tools.Release_Checks.Require_File (Checks, "hostkit.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "check_hostkit/check_hostkit.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/hostkit_check_all.gpr");

   Project_Tools.Release_Checks.Run
     ("build check_hostkit",
      Root & "/check_hostkit",
      Alr,
      GNAT.OS_Lib.Argument_List'([1 => new String'("build")]));
   Project_Tools.Release_Checks.Run
     ("hostkit release check",
      Root & "/check_hostkit",
      "./bin/check_hostkit",
      GNAT.OS_Lib.Argument_List'([]));

   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/check_hostkit/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tools/obj");

   Put_Line ("hostkit aggregate release checklist passed");
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
exception
   when Program_Error =>
      null;
   when E : others =>
      Put_Line
        (Standard_Error,
         "hostkit aggregate release checklist failed: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Check_All;
