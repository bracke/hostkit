separate (Hostkit_Shell_Cases)
procedure Test_Locking_Does_Not_Truncate
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path   : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory,
                              "hostkit-lock-keeps.tmp");
   Item   : D.Descriptor;
   Sent   : constant Ada.Streams.Stream_Element_Array (1 .. 4) := [100, 97, 116, 97];
   Last   : Ada.Streams.Stream_Element_Offset;
   --  Set by a call whose success is what is asserted, not its result.
   pragma Warnings (Off, Last);
   Held   : Hostkit.Locks.Lock;
   Taken  : Hostkit.Locks.Lock_Outcome;
begin
   Assert (D.Open_File (Path, D.Open_Write_Truncate, Item), "could not create the file");
   Assert (D.Write (Item, Sent, Last) = D.Transfer_Ok, "could not write the file");
   D.Close (Item);

   Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Held);

   if Taken = Hostkit.Locks.Lock_Ok then
      Hostkit.Locks.Release (Held);
   elsif Taken /= Hostkit.Locks.Lock_Unsupported then
      Assert (False, "could not lock the file: "
              & Hostkit.Locks.Lock_Outcome'Image (Taken));
   end if;

   --  A lock taken on the state file itself must not destroy the state it is
   --  protecting. Opening with O_TRUNC here would do exactly that, silently,
   --  and only for the caller that locked before reading.
   Assert (Ada.Directories.Size (Path) = 4,
           "taking a lock truncated the file it was protecting");

   Ada.Directories.Delete_File (Path);
end Test_Locking_Does_Not_Truncate;
