with Interfaces;
with Interfaces.C;
with System;

--  What the Linux and macOS bodies share below the level of a public unit:
--  the calling thread's errno, and the children started detached that are
--  still to be collected. Every body that reads or sets errno used to
--  bind the per-thread location itself, each copy naming the host's symbol;
--  it is bound once here, and the one name that differs between the hosts
--  comes from Hostkit.Posix_Abi. This package is in the POSIX source
--  directory only, so no other host ever sees it.
private package Hostkit.Posix is

   --  The calling thread's errno.
   --
   --  @return The value errno holds now.
   function Errno return Interfaces.C.int;

   --  Set the calling thread's errno.
   --
   --  @param Code The value to give it; 0 clears it.
   procedure Set_Errno (Code : Interfaces.C.int);

   --  Remember a child started detached -- by Hostkit.Process.Launch or by
   --  Open_Native -- so that Reap_Noted_Children collects it once it has
   --  finished. Only a child noted here is ever collected by that: a child
   --  that Hostkit.Spawn or Run_Captured started is theirs to wait for, and a
   --  waitpid on any child would take its status from under them.
   --
   --  @param Process_Id The child's process id.
   procedure Note_Child (Process_Id : Integer);

   --  Collect each noted child that has already finished, and forget it.
   --  Never waits for one still running; that one stays noted for next time.
   procedure Reap_Noted_Children;

   --  Read an open directory to its end with Readdir, handing each entry to
   --  Visit. readdir answers NULL both at the end and when the read fails
   --  part-way (EIO on a failing disk, ESTALE on a lost share); only errno,
   --  cleared before each call, tells the two apart. A listing cut short by
   --  a failure is not a shorter listing.
   --
   --  @param Directory The open directory (a DIR *).
   --  @return True when the directory was read to its end, or Visit stopped
   --  the read; False when a read failed.
   generic
      --  readdir on Directory: the next entry (a struct dirent *), or NULL.
      with function Readdir (Directory : System.Address) return System.Address;
      --  One entry. False stops the read there, as a success.
      with function Visit (Item : System.Address) return Boolean;
   function Read_Directory (Directory : System.Address) return Boolean;

   --  A count the host gives as an unsigned 64-bit number, held in the
   --  Natural the caller reports it as. A filesystem that does not count --
   --  FUSE and network ones answer UINT64_MAX -- would overflow the
   --  conversion and raise, and the raise would take every other answer of
   --  the same call with it; the largest Natural is the honest "at least".
   --
   --  @param Value The host's count.
   --  @return Value, or Natural'Last when it is larger.
   function Saturating_Natural (Value : Interfaces.Unsigned_64) return Natural;

   --  The same for a count held in a Long_Long_Integer.
   --
   --  @param Value The host's count.
   --  @return Value, or Long_Long_Integer'Last when it is larger.
   function Saturating_Count (Value : Interfaces.Unsigned_64) return Long_Long_Integer;

   --  Blocks of Unit_Size bytes, in bytes, without overflowing: a product
   --  past Long_Long_Integer'Last is Long_Long_Integer'Last.
   --
   --  @param Blocks How many blocks.
   --  @param Unit_Size The size of one, in bytes.
   --  @return The byte count; 0 when either is 0.
   function Saturating_Byte_Count (Blocks, Unit_Size : Interfaces.Unsigned_64) return Long_Long_Integer;

end Hostkit.Posix;
