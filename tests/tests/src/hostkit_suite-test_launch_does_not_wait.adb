separate (Hostkit_Suite)
procedure Test_Launch_Does_Not_Wait (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Empty : Hostkit.String_Vectors.Vector;
   Arguments : Hostkit.String_Vectors.Vector;
begin
   --  A detached launch says only that it began. It has no exit status to give, and
   --  reporting one -- as the backgrounding shell's zero used to be reported -- says
   --  nothing whatever about the program.
   Assert (Hostkit.Process.Launch (Companion ("noop"), Empty), "a launch that starts says so");
   Arguments.Append (To_Unbounded_String ("one argument"));
   Arguments.Append (To_Unbounded_String ("quoted ""argument"""));
   Assert
     (Hostkit.Process.Launch (Companion ("noop"), Arguments),
      "a detached argument vector starts without shell reinterpretation");
   Assert
     (not Hostkit.Process.Launch ("", Empty),
      "a launch with no program to run does not claim to have started");
end Test_Launch_Does_Not_Wait;
