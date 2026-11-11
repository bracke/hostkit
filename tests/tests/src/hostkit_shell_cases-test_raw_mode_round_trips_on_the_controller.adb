separate (Hostkit_Shell_Cases)
procedure Test_Raw_Mode_Round_Trips_On_The_Controller
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item   : Hostkit.Pty.Pair;
   Before : Hostkit.Terminal_Control.Mode;
   After  : Hostkit.Terminal_Control.Mode;
   Again  : Hostkit.Terminal_Control.Mode;
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   Assert (Hostkit.Pty.Open (Item), "could not open a pseudo-terminal");

   if not D.Is_Terminal (Item.From_Child) then
      --  A host whose parent side is a pipe rather than a terminal: there
      --  are no line-discipline settings to save, and asking for them is
      --  what Is_Terminal is for. The console keeps the modes there, and
      --  the child's end of it is what has them.
      Hostkit.Pty.Close (Item);
      return;
   end if;

   Assert (Hostkit.Terminal_Control.Save_Mode (Item.From_Child, Before),
           "could not save the controller's settings");
   Assert (Hostkit.Terminal_Control.Set_Raw (Item.From_Child),
           "could not set raw mode on the controller");
   Assert (Hostkit.Terminal_Control.Restore_Mode (Item.From_Child, Before),
           "could not restore the controller's settings");
   Assert (Hostkit.Terminal_Control.Save_Mode (Item.From_Child, After),
           "could not re-read the controller's settings");

   Assert (Hostkit.Terminal_Control.Set_Raw (Item.From_Child),
           "could not set raw mode on the controller a second time");
   Assert (Hostkit.Terminal_Control.Restore_Mode (Item.From_Child, Before),
           "could not restore the controller's settings a second time");
   Assert (Hostkit.Terminal_Control.Save_Mode (Item.From_Child, Again),
           "could not re-read the controller's settings a second time");

   Assert (After = Again,
           "restoring the controller's settings twice reached two different "
           & "terminals");

   Hostkit.Pty.Close (Item);
end Test_Raw_Mode_Round_Trips_On_The_Controller;
