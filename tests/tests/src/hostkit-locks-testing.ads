with Interfaces;

--  A test's view of a held lock: the host value of the open file it lives
--  on, so a test can ask the host about that file -- whether a program
--  started meanwhile would inherit it -- where no listing of a program's
--  open files exists to ask instead.
package Hostkit.Locks.Testing is

   --  The host value of Item's open file: a descriptor on POSIX, a HANDLE on
   --  Windows.
   --
   --  @param Item A lock.
   --  @return That value, or -1 when Item is not held.
   function Host_Handle (Item : Lock) return Interfaces.Integer_64;

end Hostkit.Locks.Testing;
