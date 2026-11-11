with Ada.Streams.Stream_IO.C_Streams;

--  The same on every host: what differs, the open, is each host's
--  C_Stream_For.
separate (Hostkit.Fs)
procedure Open_Stream
  (File : in out Ada.Streams.Stream_IO.File_Type;
   Mode : Ada.Streams.Stream_IO.File_Mode;
   Path : String)
is
   use type Ada.Streams.Stream_IO.Count;
   use type Ada.Streams.Stream_IO.File_Mode;
   Stream  : Interfaces.C_Streams.FILEs;
   Ignored : Interfaces.C_Streams.int;
begin
   if Ada.Streams.Stream_IO.Is_Open (File) then
      raise Ada.IO_Exceptions.Status_Error with "Open_Stream: the file is already open";
   end if;
   --  GNAT's own fopen modes: "r+" for writing, so Out_File does not
   --  truncate, and Append_File is placed at the end below.
   Stream := C_Stream_For (Path, (if Mode = Ada.Streams.Stream_IO.In_File then "r" else "r+"), Text => False);
   begin
      Ada.Streams.Stream_IO.C_Streams.Open
        (File, Mode, Stream,
         Form => "shared=no",
         Name => (if Path'Length <= Interfaces.C_Streams.max_path_len then Path else ""));
   exception
      when others =>
         Ignored := Interfaces.C_Streams.fclose (Stream);
         raise;
   end;
   --  C_Streams.Open leaves the stream's index at its start; a write would
   --  go there rather than after the end.
   if Mode = Ada.Streams.Stream_IO.Append_File then
      Ada.Streams.Stream_IO.Set_Index (File, Ada.Streams.Stream_IO.Size (File) + 1);
   end if;
end Open_Stream;
