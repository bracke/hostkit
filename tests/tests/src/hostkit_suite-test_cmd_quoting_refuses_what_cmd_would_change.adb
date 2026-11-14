separate (Hostkit_Suite)
procedure Test_Cmd_Quoting_Refuses_What_Cmd_Would_Change
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   --  One double-quote character, so the expectations read.
   DQ        : constant String := """";
   Arguments : Hostkit.String_Vectors.Vector;
   Status    : Integer := -1;
begin
   --  The quoting itself is text, and the same on every host.
   Assert (Hostkit.Shell.Cmd_Quote ("a b") = DQ & "a b" & DQ, "cmd groups with double quotes");
   Assert (Hostkit.Shell.Cmd_Quote ("") = DQ & DQ, "an empty argument is quoted, not refused");
   Assert (Hostkit.Shell.Cmd_Quote ("say " & DQ & "hi" & DQ) = DQ & "say " & DQ & DQ & "hi" & DQ & DQ & DQ,
           "an embedded double quote is doubled");
   Assert (Hostkit.Shell.Cmd_Quote ("100% sure") = "", "a % is refused: cmd expands %NAME% inside quotes");
   Assert (Hostkit.Shell.Cmd_Quote ("%PATH%") = "", "a variable's name is refused, not expanded");
   Assert (Hostkit.Shell.Cmd_Quote ("one" & ASCII.LF & "two") = "", "a line feed would end the command");
   Assert (Hostkit.Shell.Cmd_Quote ("one" & ASCII.CR & "two") = "", "and so would a carriage return");
   Assert (Hostkit.Shell.Cmd_Quote ("a&b|c<d>e^f!g") = DQ & "a&b|c<d>e^f!g" & DQ,
           "cmd's other specials are plain text inside the quotes");

   --  sh has no such hole: inside single quotes % is text.
   Assert (Hostkit.Shell.Sh_Quote ("100% sure") = "'100% sure'", "sh keeps a %");
   Assert (Hostkit.Shell.Sh_Quote ("one" & ASCII.LF & "two") = "'one" & ASCII.LF & "two'", "and a line feed");
   Assert (Hostkit.Shell.Sh_Quote ("a" & ASCII.NUL) = "", "a NUL no command line can carry");

   --  This host's Quote is one of the two, and a refusal travels: the whole
   --  command line is refused, and running it is refused too.
   Assert (Hostkit.Shell.Can_Quote ("100% sure") = not Hostkit.Shell.Is_Command_Shell,
           "this host's shell refuses a % exactly when it is cmd");
   Arguments.Append (To_Unbounded_String ("%PATH%"));
   if Hostkit.Shell.Is_Command_Shell then
      Assert (Hostkit.Shell.Command_Line (Companion ("noop"), Arguments) = "",
              "a command line with an argument cmd would expand is refused whole");
      Assert (not Hostkit.Process.Run_Shell_Command
                (Hostkit.Shell.Command_Line (Companion ("noop"), Arguments), Wait => True, Exit_Status => Status),
              "and a refused command line is not run");
   else
      Assert (Hostkit.Process.Run_Shell_Command
                (Hostkit.Shell.Command_Line (Companion ("noop"), Arguments), Wait => True, Exit_Status => Status)
              and then Status = 0,
              "sh runs an argument with % in it as it is");
   end if;
end Test_Cmd_Quoting_Refuses_What_Cmd_Would_Change;
