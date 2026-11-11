separate (Hostkit_Suite)
procedure Test_Lease_File_Pins_Locks_And_Transfers_Bytes
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Streams.Stream_Element_Array;
   use type Hostkit.Lease_Files.Lease_Identity;
   use type Hostkit.Lease_Files.Open_Outcome;
   Path : constant String :=
     Ada.Directories.Compose (Scratch, "hk-secure-lease");
   First, Second : Hostkit.Lease_Files.Lease;
   --  Longer than any lock bookkeeping a host might keep in the file, so
   --  the holder's own writes and reads are proven not to collide with it.
   Written : constant Ada.Streams.Stream_Element_Array (1 .. 64) :=
     [for Index in 1 .. 64 => Ada.Streams.Stream_Element (Index)];
   Read_Back : Ada.Streams.Stream_Element_Array (1 .. 64);
   Id : Hostkit.Lease_Files.Lease_Identity;
   Outcome : Hostkit.Lease_Files.Open_Outcome;
begin
   if Ada.Directories.Exists (Path) then
      Ada.Directories.Delete_File (Path);
   end if;
   Outcome := Hostkit.Lease_Files.Create (Path, First);
   if Outcome = Hostkit.Lease_Files.Unsupported then
      Skip ("Test_Lease_File_Pins_Locks_And_Transfers_Bytes", "the scratch volume carries no locks");
      return;
   end if;
   Assert (Outcome = Hostkit.Lease_Files.Opened,
           "a fresh secure lease is created and locked");
   Assert (Hostkit.Lease_Files.Write_At (First, Written),
           "lease bytes are written durably");
   Assert (Hostkit.Lease_Files.Size (First) = 64,
           "the held lease reports its size");
   Assert (Hostkit.Lease_Files.Read_At (First, Read_Back),
           "lease bytes are read through the held file");
   Assert (Read_Back = Written, "lease bytes round-trip exactly");
   Id := Hostkit.Lease_Files.Identity (First);
   Assert (Id.Available, "the held lease has a stable identity");
   Assert (Hostkit.Lease_Files.Path_Matches (First, Path),
           "the current path still names the held lease");

   Outcome := Hostkit.Lease_Files.Open
     (Path, Hostkit.Lease_Files.Exclusive, True, Second);
   Assert (Outcome = Hostkit.Lease_Files.Busy,
           "an exclusive claimant cannot pass a live shared lease");
   Assert (not Hostkit.Lease_Files.Is_Held (Second),
           "a busy claim retains no handle");
   Hostkit.Lease_Files.Release (First);
   Outcome := Hostkit.Lease_Files.Open
     (Path, Hostkit.Lease_Files.Exclusive, True, Second);
   Assert (Outcome = Hostkit.Lease_Files.Opened,
           "the lease becomes claimable when its owner releases it");
   Assert (Hostkit.Lease_Files.Identity (Second) = Id,
           "reopening retains the same file identity");
   Hostkit.Lease_Files.Release (Second);
   Ada.Directories.Delete_File (Path);
end Test_Lease_File_Pins_Locks_And_Transfers_Bytes;
