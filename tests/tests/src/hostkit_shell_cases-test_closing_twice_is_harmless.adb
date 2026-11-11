separate (Hostkit_Shell_Cases)
procedure Test_Closing_Twice_Is_Harmless
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Ends : D.Pipe_Ends;
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");

   D.Close (Ends.Read_End);
   Assert (not D.Is_Valid (Ends.Read_End), "Close left the descriptor valid");

   --  The second close must not reach the host at all. If it did, and the
   --  number had been reused by then, it would close something else -- the
   --  bug this design removes rather than documents.
   D.Close (Ends.Read_End);
   Assert (not D.Is_Valid (Ends.Read_End), "closing twice revived the descriptor");

   D.Close (Ends.Write_End);
end Test_Closing_Twice_Is_Harmless;
