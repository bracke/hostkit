separate (Hostkit_Suite)
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
