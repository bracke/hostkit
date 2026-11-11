separate (Hostkit_Shell_Cases)
procedure Test_Raw_Mode_Round_Trips
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item   : Hostkit.Pty.Pair;
   Before : Hostkit.Terminal_Control.Mode;
   Raw    : Hostkit.Terminal_Control.Mode;
   After  : Hostkit.Terminal_Control.Mode;
   Again  : Hostkit.Terminal_Control.Mode;
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   --  Done on a pseudo-terminal rather than on the suite's own standard
   --  input: a test that put the developer's real terminal into raw mode and
   --  then failed an assertion would leave them typing `reset` blind.
   Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

   if not Has_A_Device_Side (Item) then
      Hostkit.Pty.Close (Item);
      return;
   end if;

   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Before),
           "could not save the terminal settings");
   Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
           "could not set raw mode");
   Assert (Hostkit.Terminal_Control.Discard_Input (Item.Device),
           "could not discard a terminal's unread input");
   --  Typed input kept past an interrupt where the host is known to
   --  flush it, and let go again; a pipe is no terminal to arrange.
   if Hostkit.Terminal_Control.Set_Echo (Item.Device, On => False) then
      Assert (Hostkit.Terminal_Control.Set_Echo (Item.Device, On => True),
              "echo turned off could not be turned on again");
   end if;
   if Hostkit.Terminal_Control.Show_Control_Keys (Item.Device, On => False) then
      Assert (Hostkit.Terminal_Control.Show_Control_Keys (Item.Device, On => True),
              "control keys hidden could not be shown again");
   end if;
   if Hostkit.Terminal_Control.Keep_Input_On_Interrupt (Item.Device, Keep => True) then
      Assert (Hostkit.Terminal_Control.Keep_Input_On_Interrupt (Item.Device, Keep => False),
              "typed input kept past an interrupt could not be let go again");
   end if;

   --  Raw is a different terminal from the one that was saved. Asked before
   --  the restore because a Set_Raw that changed nothing would make the
   --  round-trip below pass for the wrong reason -- and on a host where the
   --  round-trip fails, it says whether the going or the coming back is at
   --  fault.
   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Raw),
           "could not read back the raw settings");
   Assert (Before /= Raw,
           "setting raw mode changed nothing this host will admit to");

   Assert (Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before),
           "could not restore the terminal settings");

   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, After),
           "could not re-read the terminal settings");

   --  Not `Before = After`. A saved mode holds host state as well as
   --  settings -- macOS keeps PENDIN in it -- so a restore that applied
   --  every setting can still read back as something else, and asserting
   --  byte equality tests the host's state bits rather than this crate.
   --
   --  What is asked instead is that the restore is not a no-op and is
   --  repeatable: it moved the terminal away from raw, and going round
   --  again lands in the same place. A restore that did nothing would leave
   --  After equal to Raw, and one that landed somewhere new each time would
   --  not agree with itself.
   Assert (After /= Raw,
           "restoring left the terminal in raw mode");

   Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
           "could not set raw mode a second time");
   Assert (Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before),
           "could not restore the terminal settings a second time");
   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Again),
           "could not re-read the terminal settings a second time");

   Assert (After = Again,
           "restoring the same saved settings twice reached two different "
           & "terminals");

   Hostkit.Pty.Close (Item);
end Test_Raw_Mode_Round_Trips;
