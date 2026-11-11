separate (Hostkit_Suite)
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
