separate (Hostkit_Shell_Cases)
procedure Test_Shared_Locks_Coexist
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path   : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory,
                              "hostkit-lock-shared.tmp");
   First  : Hostkit.Locks.Lock;
   Second : Hostkit.Locks.Lock;
   Taken  : Hostkit.Locks.Lock_Outcome;
begin
   Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Shared, False, First);

   if Taken = Hostkit.Locks.Lock_Unsupported then
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "the local disk carries locks");
      return;
   end if;

   Assert (Taken = Hostkit.Locks.Lock_Ok, "could not take a shared lock");

   --  Two readers at once is the point of a shared lock. If this refused,
   --  loading state would serialise every session for no reason.
   Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Shared, False, Second);
   Assert (Taken = Hostkit.Locks.Lock_Ok,
           "a second shared lock was refused: "
           & Hostkit.Locks.Lock_Outcome'Image (Taken));

   Hostkit.Locks.Release (First);
   Hostkit.Locks.Release (Second);

   Ada.Directories.Delete_File (Path);
end Test_Shared_Locks_Coexist;
