separate (Hostkit_Shell_Cases)
procedure Test_What_A_Host_Does_Not_Put_Back
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item   : Hostkit.Pty.Pair;
   Before : Hostkit.Terminal_Control.Mode;
   After  : Hostkit.Terminal_Control.Mode;
   Again  : Hostkit.Terminal_Control.Mode;

   Was, Became : Interfaces.Unsigned_8;
   Restored    : Boolean;
   Where       : Natural;
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

   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Before),
           "could not save the terminal settings");
   Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
           "could not set raw mode");

   Restored := Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before);

   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, After),
           "could not re-read the terminal settings");

   --  Round again. What a host may do is keep a state bit of its own -- and
   --  then it keeps the same one every time. What it may not do is lose a
   --  setting, which would show as the two journeys landing in different
   --  places.
   Assert (Hostkit.Terminal_Control.Set_Raw (Item.Device),
           "could not set raw mode a second time");
   Restored := Restored
     and then Hostkit.Terminal_Control.Restore_Mode (Item.Device, Before);
   Assert (Hostkit.Terminal_Control.Save_Mode (Item.Device, Again),
           "could not re-read the terminal settings a second time");

   Where := Hostkit.Terminal_Control.Differences.First_Difference
              (Before, After, Was, Became);

   --  The message carries the diagnosis whether or not this host needed
   --  one: a run that fails somewhere else can be read without a second
   --  trip through CI.
   Assert (After = Again,
           "two restores of the same saved settings reached two different"
           & " terminals; the first differs from what was saved at byte"
           & Natural'Image (Where) & ", which was"
           & Interfaces.Unsigned_8'Image (Was) & " and came back as"
           & Interfaces.Unsigned_8'Image (Became)
           & "; Restore_Mode answered " & Boolean'Image (Restored));

   Hostkit.Pty.Close (Item);
end Test_What_A_Host_Does_Not_Put_Back;
