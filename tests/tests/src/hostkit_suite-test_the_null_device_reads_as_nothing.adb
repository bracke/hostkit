separate (Hostkit_Suite)
procedure Test_The_Null_Device_Reads_As_Nothing
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Handle : Hostkit.Descriptors.Descriptor;
   Buffer : Ada.Streams.Stream_Element_Array (1 .. 16);
   Last   : Ada.Streams.Stream_Element_Offset;

   use type Hostkit.Descriptors.Transfer_Outcome;
begin
   if Hostkit.Fs.Null_Device = "" then
      --  A host this crate knows nothing about is not promised one.
      Skip ("Test_The_Null_Device_Reads_As_Nothing", "this host has no null device");
      return;
   end if;

   Assert (Hostkit.Descriptors.Open_File
             (Hostkit.Fs.Null_Device,
              Hostkit.Descriptors.Open_Read, Handle),
           "the null device would not open for reading: "
           & Hostkit.Fs.Null_Device);

   Assert (Hostkit.Descriptors.Read (Handle, Buffer, Last)
           = Hostkit.Descriptors.Transfer_End_Of_File,
           "the null device did not read as nothing");

   Hostkit.Descriptors.Close (Handle);

   --  And it takes what is written to it, which is the other half of what
   --  a caller with nothing to give needs.
   Assert (Hostkit.Descriptors.Open_File
             (Hostkit.Fs.Null_Device,
              Hostkit.Descriptors.Open_Write_Truncate, Handle),
           "the null device would not open for writing");

   declare
      Written : constant Ada.Streams.Stream_Element_Array (1 .. 4) :=
        [1, 2, 3, 4];

      Took : constant Boolean :=
        Hostkit.Descriptors.Write (Handle, Written, Last)
        = Hostkit.Descriptors.Transfer_Ok;

      use type Ada.Streams.Stream_Element_Offset;
   begin
      Assert (Took and then Last = Written'Last,
              "the null device would not take what was written to it");
   end;

   --  The checked close says how the close went, and leaves the handle
   --  invalid, so that closing it again closes nothing and answers True.
   Assert (Hostkit.Descriptors.Close (Handle),
           "the null device's close was reported as failed");
   Assert (not Hostkit.Descriptors.Is_Valid (Handle)
           and then Hostkit.Descriptors.Close (Handle),
           "a closed descriptor was not left invalid");
end Test_The_Null_Device_Reads_As_Nothing;
