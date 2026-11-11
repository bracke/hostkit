separate (Hostkit_Shell_Cases)
procedure Test_Cursor_Control_Writes_To_A_Pseudo_Terminal
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Item  : Hostkit.Pty.Pair;
   Into  : Ada.Streams.Stream_Element_Array (1 .. 64);
   Last  : Ada.Streams.Stream_Element_Offset;
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

   Assert (Hostkit.Terminal_Control.Supports_Cursor_Control (Item.Device),
           "a pseudo-terminal refused cursor control");

   --  A movement of zero writes nothing and is not a failure. A caller that
   --  computed a distance of zero would otherwise emit "move left zero",
   --  which some terminals read as "move left one".
   Assert (Hostkit.Terminal_Control.Control
             (Item.Device, Hostkit.Terminal_Control.Move_Left, 0),
           "a zero-distance move was reported as a failure");

   Assert (Hostkit.Terminal_Control.Control
             (Item.Device, Hostkit.Terminal_Control.Erase_To_End_Of_Line),
           "erase-to-end-of-line was refused by a pseudo-terminal");

   --  Something arrived, and it is not the caller's business what. The point
   --  of the check is that the action reached the terminal at all: an action
   --  that silently wrote nothing would leave a line editor redrawing over
   --  its own previous output.
   case D.Read (Item.From_Child, Into, Last) is
      when D.Transfer_Ok =>
         Assert (Last >= Into'First,
                 "a cursor action wrote no bytes to the terminal");
      when others =>
         Assert (False, "could not read back what the cursor action wrote");
   end case;

   --  A screen of its own, and back: both reach the terminal.
   Assert (Hostkit.Terminal_Control.Control
             (Item.Device, Hostkit.Terminal_Control.Enter_Alternate_Screen)
           and then Hostkit.Terminal_Control.Control
                      (Item.Device, Hostkit.Terminal_Control.Leave_Alternate_Screen),
           "the alternate screen was refused by a pseudo-terminal");
   case D.Read (Item.From_Child, Into, Last) is
      when D.Transfer_Ok =>
         Assert (Last >= Into'First, "switching screens wrote no bytes to the terminal");
      when others =>
         Assert (False, "could not read back what switching screens wrote");
   end case;

   Hostkit.Pty.Close (Item);
end Test_Cursor_Control_Writes_To_A_Pseudo_Terminal;
