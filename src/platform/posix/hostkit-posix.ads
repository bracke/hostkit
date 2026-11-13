with Interfaces.C;

--  What the Linux and macOS bodies share below the level of a public unit:
--  the calling thread's errno. Every body that reads or sets errno used to
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

end Hostkit.Posix;
