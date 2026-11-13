with System;

with Hostkit.Posix_Abi;

package body Hostkit.Posix is

   --  errno is a macro over a per-thread location; the function it expands
   --  to answers that location's address, and its name is the host's.
   function Errno_Location return System.Address
     with Import => True, Convention => C, External_Name => Hostkit.Posix_Abi.Errno_Location;

   -----------
   -- Errno --
   -----------

   function Errno return Interfaces.C.int is
      Value : Interfaces.C.int
        with Import => True, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   ---------------
   -- Set_Errno --
   ---------------

   procedure Set_Errno (Code : Interfaces.C.int) is
      Value : Interfaces.C.int
        with Import => True, Address => Errno_Location;
   begin
      Value := Code;
   end Set_Errno;

end Hostkit.Posix;
