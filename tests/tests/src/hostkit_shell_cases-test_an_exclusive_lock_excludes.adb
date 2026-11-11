separate (Hostkit_Shell_Cases)
procedure Test_An_Exclusive_Lock_Excludes
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path   : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory,
                              "hostkit-lock-test.tmp");
   First  : Hostkit.Locks.Lock;
   Second : Hostkit.Locks.Lock;
   Taken  : Hostkit.Locks.Lock_Outcome;
begin
   Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, First);

   if Taken = Hostkit.Locks.Lock_Unsupported then
      --  A filesystem that does not carry locks. Reported, not pretended;
      --  but the test's own folder is a local disk on every host built
      --  for, so there it is a failure.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "the local disk carries locks");
      return;
   end if;

   Assert (Taken = Hostkit.Locks.Lock_Ok,
           "could not take an exclusive lock: "
           & Hostkit.Locks.Lock_Outcome'Image (Taken));
   Assert (Hostkit.Locks.Is_Held (First), "the lock does not report itself held");

   --  flock is per open file description, so a second Acquire in this same
   --  process opens the file again and genuinely contends. Without this the
   --  lock could be a no-op and nothing above would notice.
   Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Second);
   Assert (Taken = Hostkit.Locks.Lock_Busy,
           "a second exclusive lock was granted: "
           & Hostkit.Locks.Lock_Outcome'Image (Taken));
   Assert (not Hostkit.Locks.Is_Held (Second),
           "a refused lock reported itself held");

   Hostkit.Locks.Release (First);
   Assert (not Hostkit.Locks.Is_Held (First), "Release left the lock held");

   --  And once released it is available again.
   Taken := Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Second);
   Assert (Taken = Hostkit.Locks.Lock_Ok,
           "the lock was not available after being released");
   Hostkit.Locks.Release (Second);

   --  Releasing twice must be harmless, like closing a descriptor twice, or
   --  an error path releases something a later Acquire has taken.
   Hostkit.Locks.Release (Second);

   Ada.Directories.Delete_File (Path);
end Test_An_Exclusive_Lock_Excludes;
