with Ada.Text_IO.C_Streams;

--  The same on every host: what differs, the open, is each host's
--  C_Stream_For.
separate (Hostkit.Fs)
procedure Open_Text
  (File : in out Ada.Text_IO.File_Type;
   Mode : Ada.Text_IO.File_Mode;
   Path : String)
is
   Stream  : Interfaces.C_Streams.FILEs;
   Ignored : Interfaces.C_Streams.int;
begin
   if Ada.Text_IO.Is_Open (File) then
      raise Ada.IO_Exceptions.Status_Error with "Open_Text: the file is already open";
   end if;
   --  GNAT's own fopen modes for Text_IO: Out_File empties the file, and
   --  Append_File is placed at its end by the runtime as the file is taken.
   Stream := C_Stream_For
     (Path,
      (case Mode is
          when Ada.Text_IO.In_File     => "r",
          when Ada.Text_IO.Out_File    => "w",
          when Ada.Text_IO.Append_File => "r+"),
      Text => True);
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
end Open_Text;
