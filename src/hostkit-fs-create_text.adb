with Ada.Text_IO.C_Streams;

--  The same on every host: what differs, the open, is each host's
--  C_Stream_For.
separate (Hostkit.Fs)
procedure Create_Text
  (File : in out Ada.Text_IO.File_Type;
   Mode : Ada.Text_IO.File_Mode := Ada.Text_IO.Out_File;
   Path : String)
is
   use type Ada.Text_IO.File_Mode;
   Stream  : Interfaces.C_Streams.FILEs;
   Ignored : Interfaces.C_Streams.int;
begin
   if Ada.Text_IO.Is_Open (File) then
      raise Ada.IO_Exceptions.Status_Error with "Create_Text: the file is already open";
   end if;
   --  GNAT's own fopen modes for a create.
   Stream := C_Stream_For (Path, (if Mode = Ada.Text_IO.Out_File then "w" else "w+"), Text => True);
   begin
      Ada.Text_IO.C_Streams.Open
        (File, Mode, Stream,
         Form => "shared=no",
         Name => (if Path'Length <= Interfaces.C_Streams.max_path_len then Path else ""));
   exception
      when others =>
         Ignored := Interfaces.C_Streams.fclose (Stream);
         raise;
   end;
end Create_Text;
