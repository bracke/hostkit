package body Hostkit.Signals is

   --  A host this build does not know. There is no signal facility to reach,
   --  so every operation refuses. Is_Supported says so in advance, which is
   --  the call a consumer should be making.

   function Is_Supported (Item : Signal) return Boolean is
      pragma Unreferenced (Item);
   begin
      return False;
   end Is_Supported;

   function Number (Item : Signal) return Integer is
      pragma Unreferenced (Item);
   begin
      --  -1, not a plausible POSIX number. A consumer that printed a number
      --  this host does not have would be inventing one.
      return -1;
   end Number;

   function From_Number (Value : Integer; Item : out Signal) return Boolean is
      pragma Unreferenced (Value);
   begin
      Item := Signal_Terminate;
      return False;
   end From_Number;

   --  Names are host-independent identifiers, not the host's spelling, so they
   --  are answerable even where the signals themselves are not. A diagnostic
   --  that has to say what a status meant still works.
   function Name (Item : Signal) return String is
   begin
      case Item is
         when Signal_Interrupt        => return "INTERRUPT";
         when Signal_Quit             => return "QUIT";
         when Signal_Terminate        => return "TERMINATE";
         when Signal_Kill             => return "KILL";
         when Signal_Hangup           => return "HANGUP";
         when Signal_Stop             => return "STOP";
         when Signal_Terminal_Stop    => return "TERMINAL_STOP";
         when Signal_Continue         => return "CONTINUE";
         when Signal_Pipe             => return "PIPE";
         when Signal_Background_Read  => return "BACKGROUND_READ";
         when Signal_Background_Write => return "BACKGROUND_WRITE";
         when Signal_Window_Change    => return "WINDOW_CHANGE";
         when Signal_Child            => return "CHILD";
      end case;
   end Name;

   function Send_To_Process (Process_Id : Integer; Item : Signal) return Boolean is
      pragma Unreferenced (Process_Id, Item);
   begin
      return False;
   end Send_To_Process;

   function Send_To_Group (Group_Id : Integer; Item : Signal) return Boolean is
      pragma Unreferenced (Group_Id, Item);
   begin
      return False;
   end Send_To_Group;

   function Set_Disposition (Item : Signal; To : Disposition) return Boolean is
      pragma Unreferenced (Item, To);
   begin
      return False;
   end Set_Disposition;

   function Current_Disposition (Item : Signal; To : out Disposition) return Boolean is
      pragma Unreferenced (Item);
   begin
      To := Disposition_Default;
      return False;
   end Current_Disposition;

   function Can_Record (Item : Signal) return Boolean is
      pragma Unreferenced (Item);
   begin
      return False;
   end Can_Record;

   --------------
   -- Arrived --
   --------------

   function Arrived (Item : Signal) return Boolean is
      pragma Unreferenced (Item);
   begin
      --  Nothing can be recorded because nothing can be installed. False is
      --  the honest answer rather than a flag nobody ever sets, which would
      --  look like a working mechanism that simply never fires.
      return False;
   end Arrived;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : Signal) is
      pragma Unreferenced (Item);
   begin
      null;
   end Clear;

end Hostkit.Signals;
