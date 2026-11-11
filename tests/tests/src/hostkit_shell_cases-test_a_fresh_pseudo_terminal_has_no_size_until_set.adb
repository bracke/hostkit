separate (Hostkit_Shell_Cases)
procedure Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item : Hostkit.Pty.Pair;
   Size : Hostkit.Terminal_Control.Window_Size;
   --  Set by a call this test requires to refuse, so it is never read.
   pragma Warnings (Off, Size);
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

   if D.Is_Valid (Item.Device) then
      --  Fresh, it reports zero by zero, and Size refuses rather than
      --  passing that on -- the single most common way to get a
      --  pseudo-terminal wrong is to hand a child one that says it has no
      --  room. A console is made with a size instead, because the host will
      --  not make one measuring nothing.
      Assert (not Hostkit.Terminal_Control.Size (Item.Device, Size),
              "an unsized pseudo-terminal reported a size");
   end if;

   Assert (Hostkit.Pty.Set_Size (Item, (Rows => 24, Columns => 80)),
           "could not set the pseudo-terminal size");

   if not D.Is_Valid (Item.Device) then
      --  Nothing to ask on a host with no device side: what the console was
      --  told is between it and the child it redraws.
      Hostkit.Pty.Close (Item);
      return;
   end if;

   Assert (Hostkit.Terminal_Control.Size (Item.Device, Size),
           "a sized pseudo-terminal would not report its size");
   Assert (Size.Rows = 24 and then Size.Columns = 80,
           "the pseudo-terminal reported a size it was not given:"
           & Integer'Image (Size.Rows) & " by" & Integer'Image (Size.Columns));

   Hostkit.Pty.Close (Item);
end Test_A_Fresh_Pseudo_Terminal_Has_No_Size_Until_Set;
