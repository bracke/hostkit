separate (Hostkit_Shell_Cases)
procedure Test_A_Pipe_Has_No_Terminal_Answers
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Ends  : D.Pipe_Ends;
   Size  : Hostkit.Terminal_Control.Window_Size;
   --  Set by a call this test requires to refuse, so it is never read.
   pragma Warnings (Off, Size);
   Group : Integer;
   Saved : Hostkit.Terminal_Control.Mode;
   --  Set by a call this test requires to refuse, so it is never read.
   pragma Warnings (Off, Saved);
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");

   --  Every one of these must refuse rather than answer. A pipe has no size,
   --  and zero rows is not "how big is it" -- a caller that stored it would
   --  lay out for a terminal with no room, or divide by it.
   Assert (not D.Is_Terminal (Ends.Read_End), "a pipe claimed to be a terminal");
   Assert (not Hostkit.Terminal_Control.Size (Ends.Read_End, Size),
           "a pipe reported a window size");
   Assert (not Hostkit.Terminal_Control.Save_Mode (Ends.Read_End, Saved),
           "a pipe let its terminal settings be saved");
   Assert (not Hostkit.Terminal_Control.Set_Raw (Ends.Read_End),
           "a pipe was put into raw mode");
   Assert (not Hostkit.Terminal_Control.Discard_Input (Ends.Read_End),
           "a pipe had its typed input discarded as a terminal's");
   Assert (not Hostkit.Terminal_Control.Set_Echo (Ends.Read_End, On => False),
           "a pipe had its echo turned off as a terminal's");
   Assert (not Hostkit.Terminal_Control.Show_Control_Keys (Ends.Read_End, On => False),
           "a pipe had its control keys hidden as a terminal's");
   Assert (not Hostkit.Terminal_Control.Keep_Input_On_Interrupt (Ends.Read_End, Keep => True),
           "a pipe was told to keep its typed input past an interrupt");

   if Hostkit.Terminal_Control.Supports_Foreground_Group then
      Assert (not Hostkit.Terminal_Control.Foreground_Group (Ends.Read_End, Group),
              "a pipe reported a foreground process group");
   end if;

   D.Close (Ends.Read_End);
   D.Close (Ends.Write_End);
end Test_A_Pipe_Has_No_Terminal_Answers;
