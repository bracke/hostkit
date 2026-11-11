separate (Hostkit_Shell_Cases)
procedure Test_A_Pipe_Wait_Tells_A_Timeout_From_A_Failure
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type D.Wait_Outcome;
   Ends : D.Pipe_Ends;
   Sent : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [33];
   Last : Ada.Streams.Stream_Element_Offset;
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");

   --  A terminal's reader decides by this whether to wait again or give up.
   Assert (D.Wait_For_Readable (Ends.Read_End, 20) = D.Wait_Timed_Out,
           "an empty pipe did not time out");
   Assert (D.Write (Ends.Write_End, Sent, Last) = D.Transfer_Ok,
           "writing to a fresh pipe failed");
   Assert (Last = Sent'Last, "a one byte write into an empty pipe was short");
   Assert (D.Wait_For_Readable (Ends.Read_End, 20) = D.Wait_Ready,
           "a pipe with a byte in it was not ready");
   Assert (D.Wait_For_Readable (D.Invalid, 20) = D.Wait_Failed,
           "waiting on no descriptor at all was not a failure");

   D.Close (Ends.Write_End);
   D.Close (Ends.Read_End);
end Test_A_Pipe_Wait_Tells_A_Timeout_From_A_Failure;
