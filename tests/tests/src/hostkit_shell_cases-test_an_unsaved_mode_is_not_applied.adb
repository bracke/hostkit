separate (Hostkit_Shell_Cases)
procedure Test_An_Unsaved_Mode_Is_Not_Applied
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item   : Hostkit.Pty.Pair;
   Unsaved : Hostkit.Terminal_Control.Mode;
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

   --  A Mode that was never filled is zeroes, and applying zeroes to a
   --  terminal is worse than leaving it raw: no baud rate, no character
   --  size, no control characters. It has to refuse.
   Assert (not Hostkit.Terminal_Control.Restore_Mode (Item.Device, Unsaved),
           "a terminal mode that was never saved was applied anyway");

   Hostkit.Pty.Close (Item);
end Test_An_Unsaved_Mode_Is_Not_Applied;
