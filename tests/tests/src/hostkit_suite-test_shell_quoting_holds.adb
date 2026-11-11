separate (Hostkit_Suite)
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
