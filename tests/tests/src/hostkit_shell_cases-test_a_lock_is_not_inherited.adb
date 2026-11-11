separate (Hostkit_Shell_Cases)
procedure Test_A_Lock_Is_Not_Inherited
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path    : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory, "hostkit-lock-kept.tmp");
   Listing : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory, "hostkit-lock-fds.txt");
   Held    : Hostkit.Locks.Lock;
   Words   : Hostkit.String_Vectors.Vector;
   Outcome : Hostkit.Process.Process_Outcome;
   File    : Ada.Text_IO.File_Type;
   Found   : Boolean := False;
begin
   --  Where a program's open files cannot be listed, there is nothing to see.
   if not Ada.Directories.Exists ("/proc/self/fd") or else not Ada.Directories.Exists ("/bin/sh") then
      Skip ("Test_A_Lock_Is_Not_Inherited", "no /proc/self/fd to list a program's open files");
      return;
   end if;
   Assert
     (Hostkit.Locks.Acquire (Path, Hostkit.Locks.Lock_Exclusive, False, Held) = Hostkit.Locks.Lock_Ok,
      "the local disk carries locks");
   Words.Append (Ada.Strings.Unbounded.To_Unbounded_String ("-c"));
   Words.Append (Ada.Strings.Unbounded.To_Unbounded_String ("ls -l /proc/$$/fd"));
   Outcome := Hostkit.Process.Run_Captured
     ("/bin/sh", Words, Stdin_Path => "/dev/null", Stdout_Path => Listing);
   Assert (Outcome.Started, "the listing did not run");
   Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Listing);
   while not Ada.Text_IO.End_Of_File (File) loop
      Found := Found
        or else Ada.Strings.Fixed.Index (Ada.Text_IO.Get_Line (File), "hostkit-lock-kept") > 0;
   end loop;
   Ada.Text_IO.Close (File);
   Hostkit.Locks.Release (Held);
   Ada.Directories.Delete_File (Path);
   Ada.Directories.Delete_File (Listing);
   Assert (not Found, "a program started while a lock was held got the lock's file");
end Test_A_Lock_Is_Not_Inherited;
