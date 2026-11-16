separate (Hostkit_Shell_Cases)
procedure Test_A_File_Round_Trips_Through_A_Descriptor
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path   : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory,
                              "hostkit-descriptor-roundtrip.tmp");
   Moved_Path : constant String := Path & ".held";
   Item   : D.Descriptor;
   Other  : D.Descriptor;
   Original_Identity : Hostkit.Metadata.Entry_Identity;
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
   Original_Identity := D.Identity_Of (Item);
   Assert
     (Original_Identity.Available
      and then Original_Identity.File_Number /= 0,
      "an open file did not expose a stable identity");
   Assert
     (Original_Identity = Hostkit.Metadata.Entry_Identity_Of (Path),
      "descriptor and pathname identities disagree");
   Assert
     (D.Positioning_Of (Item) = D.Positioning_Seekable,
      "a regular file was not classified from its descriptor as seekable");
   Assert (D.Read (Item, Buffer, Last) = D.Transfer_Ok, "reading the file failed");
   Assert (Last = 3 and then Buffer (1 .. 3) = Sent,
           "the file did not return the bytes that went in");
   Assert (D.Set_Position (Item, 1), "could not reposition the open file");
   Assert (D.Read (Item, Buffer, Last) = D.Transfer_Ok,
           "reading the repositioned file failed");
   Assert (Last = 2 and then Buffer (1 .. 2) = Sent (2 .. 3),
           "the repositioned file returned the wrong bytes");
   Assert (D.Set_Position (Item, 0), "could not rewind the open file");
   Assert (D.Advance (Item, 1) = D.Advance_Complete,
           "could not advance the open file");
   Assert (D.Read (Item, Buffer, Last) = D.Transfer_Ok,
           "reading the advanced file failed");
   Assert (Last = 2 and then Buffer (1 .. 2) = Sent (2 .. 3),
           "advancing did not skip exactly one byte");

   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Ada.Directories.Rename (Path, Moved_Path);
      Assert (D.Open_File (Path, D.Open_Write_Truncate, Other),
              "could not create a replacement file");
      D.Close (Other);
      Assert
        (D.Identity_Of (Item) = Original_Identity,
         "renaming the path changed the held descriptor identity");
      Assert (D.Open_File (Path, D.Open_Read, Other),
              "could not open the replacement file");
      Assert
        (D.Identity_Of (Other) /= Original_Identity,
         "a replacement path was mistaken for the held object");
      D.Close (Other);
   end if;
   D.Close (Item);

   case Hostkit.Host.Current is
      when Hostkit.Host.Linux | Hostkit.Host.MacOS =>
         Assert
           (D.Open_File (Path, D.Open_Read_Non_Blocking, Item),
            "POSIX refused a nonblocking read open");
         D.Close (Item);
      when Hostkit.Host.Windows =>
         Assert
           (not D.Open_File (Path, D.Open_Read_Non_Blocking, Item),
            "Windows promised unsupported synchronous nonblocking reads");
      when Hostkit.Host.Unsupported =>
         null;
   end case;
   if Hostkit.Host.Current = Hostkit.Host.Unsupported then
      Assert
        (not D.Open_File (Path, D.Open_Read_For_Following, Item),
         "an unsupported host reported a follow-safe open");
   else
      Assert
        (D.Open_File (Path, D.Open_Read_For_Following, Item),
         "the follow-safe read mode refused an ordinary file");
      D.Close (Item);
   end if;

   --  Opening a file that is not there is a refusal, not a creation.
   Assert (not D.Open_File (Path & ".absent", D.Open_Read, Item),
           "opening an absent file for reading reported success");

   Ada.Directories.Delete_File (Path);
   if Ada.Directories.Exists (Moved_Path) then
      Ada.Directories.Delete_File (Moved_Path);
   end if;
end Test_A_File_Round_Trips_Through_A_Descriptor;
