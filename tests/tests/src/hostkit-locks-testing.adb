package body Hostkit.Locks.Testing is

   function Host_Handle (Item : Lock) return Interfaces.Integer_64 is
     (if Item.Held then Item.Handle else -1);

end Hostkit.Locks.Testing;
