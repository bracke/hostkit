separate (Hostkit_Shell_Cases)
procedure Test_Cursor_Control_Refuses_A_Pipe
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Ends : D.Pipe_Ends;
begin
   Assert (D.Create_Pipe (Ends), "could not create a pipe");

   --  Nothing may be drawn on something that is not a terminal. A caller
   --  that got True here would write escape bytes into whatever is reading
   --  the pipe, and those bytes would look like data.
   Assert (not Hostkit.Terminal_Control.Supports_Cursor_Control (Ends.Write_End),
           "a pipe claimed to support cursor control");

   for Action in Hostkit.Terminal_Control.Cursor_Action loop
      Assert (not Hostkit.Terminal_Control.Control (Ends.Write_End, Action),
              "a pipe accepted the cursor action "
              & Hostkit.Terminal_Control.Cursor_Action'Image (Action));
   end loop;

   D.Close (Ends.Read_End);
   D.Close (Ends.Write_End);
end Test_Cursor_Control_Refuses_A_Pipe;
