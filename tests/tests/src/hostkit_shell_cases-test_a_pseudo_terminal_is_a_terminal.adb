separate (Hostkit_Shell_Cases)
procedure Test_A_Pseudo_Terminal_Is_A_Terminal
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item : Hostkit.Pty.Pair;
begin
   if not Hostkit.Pty.Is_Supported then
      --  A host with neither pseudo-terminals nor a console of its own. The
      --  refusal is the correct answer, and a consumer degrades on the
      --  question rather than on a failed Open.
      Skip ("Test_A_Pseudo_Terminal_Is_A_Terminal", "this host has no pseudo-terminals");
      return;
   end if;

   Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");
   Assert (D.Is_Valid (Item.To_Child) and then D.Is_Valid (Item.From_Child),
           "a pseudo-terminal handed back an invalid side for the parent");

   if D.Is_Valid (Item.Device) then
      --  A host with pseudo-terminals. The whole point of the thing: unlike
      --  a pipe, both sides are terminals, so a program that checks behaves
      --  as it does for a user.
      Assert (D.Is_Terminal (Item.Device),
              "the device side of a pseudo-terminal is not a terminal");
      Assert (D.Is_Terminal (Item.From_Child),
              "the controlling side of a pseudo-terminal is not a terminal");

      Assert (Hostkit.Pty.Device_Name (Item)'Length > 0,
              "a pseudo-terminal could not name its device side");
   else
      --  A host whose answer is a console: two ordinary pipes for the
      --  parent and a console for the child. The pipes are pipes and do not
      --  pretend otherwise -- what makes the child see a terminal is the
      --  console, not these -- and there is no device to name.
      Assert (Hostkit.Spawn.Is_Attached (Item.Console),
              "a host with no device side handed back no console either");
      Assert (Hostkit.Pty.Device_Name (Item)'Length = 0,
              "a pseudo-console named a device it has not got");
   end if;

   Hostkit.Pty.Close (Item);
   Assert (not D.Is_Valid (Item.To_Child), "Close left a parent side valid");
   Assert (not D.Is_Valid (Item.From_Child), "Close left a parent side valid");
   Assert (not D.Is_Valid (Item.Device), "Close left the device valid");
end Test_A_Pseudo_Terminal_Is_A_Terminal;
