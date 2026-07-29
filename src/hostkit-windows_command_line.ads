--  Building a Windows command line out of a program and an argument vector.
--
--  CreateProcessW takes one command-line string, not an argv, and every Windows
--  program parses it back into arguments with the Microsoft C runtime rules --
--  the same rules CommandLineToArgvW implements. Getting the quoting wrong is not
--  cosmetic: a directory path with a space and a trailing backslash
--  (C:\Program Files\) naively wrapped in quotes becomes "C:\Program Files\",
--  whose trailing backslash escapes the closing quote and merges the argument
--  with the next one. The rules that avoid this -- double the run of backslashes
--  that immediately precedes a quote (an embedded one or the closing one), escape
--  an embedded quote with a backslash -- are pure text, so they live here in the
--  shared source and are exercised on every platform, not only on the host that
--  runs them.
package Hostkit.Windows_Command_Line is

   function Quote_Argument (Value : String) return String;
   --  Value encoded so the CRT parses it back as exactly one argument. Arguments
   --  with no space, tab or quote are returned unchanged; the rest are wrapped in
   --  quotes with backslashes and quotes escaped per the CRT rules.

   function Build (Program : String; Arguments : String_Vectors.Vector) return String;
   --  The program and each argument quoted with Quote_Argument and joined by
   --  single spaces, ready to hand to CreateProcessW.

end Hostkit.Windows_Command_Line;
