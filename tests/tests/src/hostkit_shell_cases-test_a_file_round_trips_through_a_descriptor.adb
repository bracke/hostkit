separate (Hostkit_Shell_Cases)
procedure Test_A_File_Round_Trips_Through_A_Descriptor
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path   : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory,
                              "hostkit-descriptor-roundtrip.tmp");
   Item   : D.Descriptor;
   --  Set by a call this test requires to refuse, so it is never read.
   pragma Warnings (Off, Item);
   Sent   : constant Ada.Streams.Stream_Element_Array (1 .. 3) := [97, 98, 99];
   Buffer : Ada.Streams.Stream_Element_Array (1 .. 8);
   Last   : Ada.Streams.Stream_Element_Offset;
begin
   Assert (D.Open_File (Path, D.Open_Write_Truncate, Item),
           "could not open a file for writing");
   Assert (D.Write (Item, Sent, Last) = D.Transfer_Ok, "writing to the file failed");
   D.Close (Item);

   Assert (D.Open_File (Path, D.Open_Read, Item), "could not reopen the file");
   Assert (D.Read (Item, Buffer, Last) = D.Transfer_Ok, "reading the file failed");
   Assert (Last = 3 and then Buffer (1 .. 3) = Sent,
           "the file did not return the bytes that went in");
   D.Close (Item);

   --  Opening a file that is not there is a refusal, not a creation.
   Assert (not D.Open_File (Path & ".absent", D.Open_Read, Item),
           "opening an absent file for reading reported success");

   Ada.Directories.Delete_File (Path);
end Test_A_File_Round_Trips_Through_A_Descriptor;
