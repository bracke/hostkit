separate (Hostkit_Shell_Cases)
procedure Test_A_Saved_Mode_Is_Stable
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item   : Hostkit.Pty.Pair;
   Once   : Hostkit.Terminal_Control.Mode;
   Again  : Hostkit.Terminal_Control.Mode;
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

   if not Has_A_Device_Side (Item) then
      Hostkit.Pty.Close (Item);
      return;
   end if;

   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Once),
           "could not save the terminal settings");
   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Again),
           "could not save the terminal settings a second time");

   Assert (Once = Again,
           "two saves of an untouched terminal did not agree, so what a "
           & "saved mode holds is not only the settings");

   Hostkit.Pty.Close (Item);
end Test_A_Saved_Mode_Is_Stable;
