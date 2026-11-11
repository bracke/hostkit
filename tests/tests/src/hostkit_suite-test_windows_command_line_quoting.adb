separate (Hostkit_Suite)
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
