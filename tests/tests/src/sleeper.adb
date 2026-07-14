with Ada.Command_Line;
with Ada.Text_IO;

procedure Sleeper is
   --  Prints a line to each stream, then refuses to finish -- so a timeout has something
   --  real to kill, and the capture has something real to capture.
begin
   Ada.Text_IO.Put_Line ("out-line");
   Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "err-line");
   Ada.Text_IO.Flush;
   Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);

   if Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--hang"
   then
      loop
         delay 1.0;
      end loop;
   end if;
end Sleeper;
