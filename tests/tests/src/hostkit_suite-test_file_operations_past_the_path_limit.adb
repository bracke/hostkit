with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;

separate (Hostkit_Suite)
procedure Test_File_Operations_Past_The_Path_Limit
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type GNAT.OS_Lib.File_Descriptor;
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Hostkit.Fs.Entry_Kind;
   package Listing renames Hostkit.Directory_Listing;

   Long_Name : constant String (1 .. 150) := [others => 'p'];
   Top       : constant String := Ada.Directories.Compose (Scratch, "hk-long-ops");
   Short_Top : constant String := Ada.Directories.Compose (Scratch, "hk-lo");
   Middle    : constant String := Ada.Directories.Compose (Short_Top, "a");
   Inner     : constant String := Ada.Directories.Compose (Middle, "b");
   Deep      : constant String := Hostkit.Fs.Join (Hostkit.Fs.Join (Top, Long_Name), Long_Name);
   Made      : constant String := Hostkit.Fs.Join (Deep, "made");
   Nested    : constant String := Hostkit.Fs.Join (Hostkit.Fs.Join (Deep, "x"), "y");
   Raw_File  : constant String := Hostkit.Fs.Join (Made, "f.bin");
   Text_File : constant String := Hostkit.Fs.Join (Made, "t.txt");
   Data_File : constant String := Hostkit.Fs.Join (Made, "s.bin");
   --  A previous run's leftovers; nothing there is the usual answer.
   Leftover  : constant Hostkit.Fs.Delete_Tree_Outcome := Hostkit.Fs.Delete_Tree_No_Follow (Top);
   pragma Unreferenced (Leftover);

   --  Whether Entries lists Name as Kind, or as Unknown where the
   --  filesystem does not record kinds in the directory.
   function Lists
     (Entries : Listing.Entry_Vectors.Vector;
      Name    : String;
      Kind    : Listing.Entry_Kind) return Boolean is
     (for some Item of Entries => Item.Name = Name and then Item.Kind in Kind | Listing.Unknown);

   --  The bytes of the file at Path, read through Open_Stream.
   function Stream_Bytes (Path : String) return String is
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 64);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Hostkit.Fs.Open_Stream (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Read (File, Buffer, Last);
      Ada.Streams.Stream_IO.Close (File);
      return Result : String (1 .. Natural (Last)) do
         for Index in Result'Range loop
            Result (Index) := Character'Val (Buffer (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;
      end return;
   end Stream_Bytes;

   --  Write Text to an open stream.
   procedure Put (File : Ada.Streams.Stream_IO.File_Type; Text : String) is
      Bytes : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
   begin
      for Index in Bytes'Range loop
         Bytes (Index) := Character'Pos (Text (Text'First + Natural (Index) - 1));
      end loop;
      Ada.Streams.Stream_IO.Write (File, Bytes);
   end Put;

   Descriptor : GNAT.OS_Lib.File_Descriptor;
   Closed     : Boolean;
   Payload    : constant String := "past the limit";
   Stream     : Ada.Streams.Stream_IO.File_Type;
   Text       : Ada.Text_IO.File_Type;
   Entries    : Listing.Entry_Vectors.Vector;
begin
   --  The deep folder, reached by renaming short names to long ones, which
   --  every host can do whatever its path limit.
   Delete_Tree_If_Present (Short_Top);
   Ada.Directories.Create_Path (Inner);
   Assert
     (Hostkit.Fs.Move_No_Replace (Inner, Hostkit.Fs.Join (Middle, Long_Name)), "the inner folder takes a long name");
   Assert
     (Hostkit.Fs.Move_No_Replace (Middle, Hostkit.Fs.Join (Short_Top, Long_Name)), "so does the folder holding it");
   Assert (Hostkit.Fs.Move_No_Replace (Short_Top, Top), "the outer folder moves on");
   Assert (Deep'Length > 300, "the folder now lies past the old path limit");
   Assert (Hostkit.Fs.Kind_Of (Deep) = Hostkit.Fs.Directory_Entry, "the deep folder is there");

   --  Directories.
   Assert (Hostkit.Fs.Create_Directory (Made), "a directory is made past the limit");
   Assert (not Hostkit.Fs.Create_Directory (Made), "an existing directory is not made again");
   Assert (Hostkit.Fs.Create_Path (Nested), "a path of missing directories is made past the limit");
   Assert (Hostkit.Fs.Kind_Of (Nested) = Hostkit.Fs.Directory_Entry, "and is a directory");
   Assert (Hostkit.Fs.Create_Path (Nested), "a path already there is made already");

   --  A file by descriptor.
   Descriptor := Hostkit.Regular_Files.Create_New (Raw_File);
   Assert (Descriptor /= GNAT.OS_Lib.Invalid_FD, "a new file is created past the limit");
   Assert
     (GNAT.OS_Lib.Write (Descriptor, Payload'Address, Payload'Length) = Payload'Length,
      "the new file takes its bytes");
   GNAT.OS_Lib.Close (Descriptor, Closed);
   Assert (Closed, "the new file closes");
   Assert
     (Hostkit.Regular_Files.Create_New (Raw_File) = GNAT.OS_Lib.Invalid_FD,
      "a file already there is not created again");
   Assert (not Hostkit.Fs.Create_Directory (Raw_File), "nor is a directory made over it");
   Assert (not Hostkit.Fs.Create_Path (Raw_File), "nor a path through it");

   --  Streams.
   Assert (Stream_Bytes (Raw_File) = Payload, "the file reads back through a stream");
   Hostkit.Fs.Create_Stream (Stream, Ada.Streams.Stream_IO.Out_File, Data_File);
   Put (Stream, "ab");
   Ada.Streams.Stream_IO.Close (Stream);
   Hostkit.Fs.Open_Stream (Stream, Ada.Streams.Stream_IO.Append_File, Data_File);
   Put (Stream, "cd");
   Ada.Streams.Stream_IO.Close (Stream);
   Assert (Stream_Bytes (Data_File) = "abcd", "an appended stream writes after the end");
   Hostkit.Fs.Open_Stream (Stream, Ada.Streams.Stream_IO.Out_File, Data_File);
   Put (Stream, "x");
   Ada.Streams.Stream_IO.Close (Stream);
   Assert (Stream_Bytes (Data_File) = "xbcd", "an opened stream writes from the start without emptying");
   Hostkit.Fs.Create_Text (Text, Ada.Text_IO.Out_File, Text_File);
   Ada.Text_IO.Put_Line (Text, "a line");
   Ada.Text_IO.Close (Text);
   Hostkit.Fs.Open_Text (Text, Ada.Text_IO.In_File, Text_File);
   Assert (Ada.Text_IO.Get_Line (Text) = "a line", "a text file reads back its line");
   Assert (Ada.Text_IO.End_Of_File (Text), "and nothing after it");
   Ada.Text_IO.Close (Text);
   begin
      Hostkit.Fs.Open_Stream (Stream, Ada.Streams.Stream_IO.In_File, Hostkit.Fs.Join (Made, "none"));
      Ada.Streams.Stream_IO.Close (Stream);
      Assert (False, "a stream on nothing opens");
   exception
      when Ada.IO_Exceptions.Name_Error =>
         Assert (not Ada.Streams.Stream_IO.Is_Open (Stream), "a stream on nothing is Name_Error and stays closed");
   end;

   --  Listing.
   Assert (Listing.List (Made, Entries), "the long folder is listed");
   Assert (Natural (Entries.Length) = 3, "with the three files in it");
   Assert (Lists (Entries, "f.bin", Listing.Regular_File), "the new file is listed as a file");
   Assert (Lists (Entries, "s.bin", Listing.Regular_File), "the stream's file is listed");
   Assert (Lists (Entries, "t.txt", Listing.Regular_File), "the text file is listed");
   Assert (Listing.List (Deep, Entries), "the deep folder is listed");
   Assert (Lists (Entries, "made", Listing.Directory), "with the folder made in it");
   Assert (Lists (Entries, "x", Listing.Directory), "and the path made in it");

   --  Deleting.
   Assert (Hostkit.Fs.Delete_File (Raw_File), "a file past the limit is deleted");
   Assert (Hostkit.Fs.Kind_Of (Raw_File) = Hostkit.Fs.Missing_Entry, "and is gone");
   Assert (not Hostkit.Fs.Delete_File (Raw_File), "a file already gone is not deleted again");
   Assert (not Hostkit.Fs.Delete_File (Made), "a directory is not deleted as a file");
   Assert (not Hostkit.Fs.Delete_Empty_Directory (Made), "nor while it holds files");
   Assert (Hostkit.Fs.Delete_File (Data_File), "the stream's file is deleted");
   Assert (Hostkit.Fs.Delete_File (Text_File), "the text file is deleted");
   Assert (Hostkit.Fs.Delete_Empty_Directory (Made), "an emptied directory past the limit is deleted");
   Assert (Hostkit.Fs.Delete_Empty_Directory (Nested), "as is the innermost of a made path");
   Assert (Hostkit.Fs.Kind_Of (Nested) = Hostkit.Fs.Missing_Entry, "which is gone");
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Top) = Hostkit.Fs.Tree_Deleted, "the deep tree is removed");
end Test_File_Operations_Past_The_Path_Limit;
