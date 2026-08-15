with Ada.Command_Line;
with Ada.Text_IO;

with Hostkit.Descriptors;

--  Says what a child sees of the streams it was given, into a file it is told
--  to write.
--
--  Into a file, because everything else it could report through is the thing
--  under test: a child asked whether its output is a terminal cannot say so on
--  that output if the answer is that it has none. The file is opened by name,
--  which needs nothing of the streams at all.
--
--  The last line it writes is what it managed to put on its own output, so a
--  reader can tell "wrote nothing" from "could not write".
procedure Terminal_Reporter is
   Where : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1) else "");

   Report : Ada.Text_IO.File_Type;
begin
   if Where = "" then
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Ada.Text_IO.Create (Report, Ada.Text_IO.Out_File, Where);

   Ada.Text_IO.Put_Line
     (Report,
      "input="
      & Boolean'Image
          (Hostkit.Descriptors.Is_Terminal
             (Hostkit.Descriptors.Standard_Input)));
   Ada.Text_IO.Put_Line
     (Report,
      "output="
      & Boolean'Image
          (Hostkit.Descriptors.Is_Terminal
             (Hostkit.Descriptors.Standard_Output)));

   declare
      Wrote : Boolean := False;
   begin
      begin
         Ada.Text_IO.Put_Line ("reporter:on-the-terminal");
         Ada.Text_IO.Flush;
         Wrote := True;
      exception
         when others =>
            Wrote := False;
      end;

      Ada.Text_IO.Put_Line (Report, "wrote=" & Boolean'Image (Wrote));
   end;

   Ada.Text_IO.Close (Report);
end Terminal_Reporter;
