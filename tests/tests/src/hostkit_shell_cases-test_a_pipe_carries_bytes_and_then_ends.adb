separate (Hostkit_Shell_Cases)
procedure Test_A_Pipe_Carries_Bytes_And_Then_Ends
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Ends   : D.Pipe_Ends;
   Sent   : constant Ada.Streams.Stream_Element_Array (1 .. 5) :=
     [72, 101, 108, 108, 111];
   Last   : Ada.Streams.Stream_Element_Offset;
   Buffer : Ada.Streams.Stream_Element_Array (1 .. 16);
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");
   Assert (D.Is_Valid (Ends.Read_End) and then D.Is_Valid (Ends.Write_End),
           "a created pipe handed back an invalid end");

   Assert (D.Write (Ends.Write_End, Sent, Last) = D.Transfer_Ok,
           "writing to a fresh pipe failed");
   Assert (Last = Sent'Last, "a five byte write into an empty pipe was short");

   Assert (D.Read (Ends.Read_End, Buffer, Last) = D.Transfer_Ok,
           "reading back from the pipe failed");
   Assert (Last = 5 and then Buffer (1 .. 5) = Sent,
           "the pipe did not return the bytes that went in");

   --  The property a pipeline depends on: end-of-file arrives when the last
   --  write end closes, and not before.
   D.Close (Ends.Write_End);
   Assert (D.Read (Ends.Read_End, Buffer, Last) = D.Transfer_End_Of_File,
           "closing the write end did not produce end-of-file");

   D.Close (Ends.Read_End);
end Test_A_Pipe_Carries_Bytes_And_Then_Ends;
