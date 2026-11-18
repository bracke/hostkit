separate (Hostkit.Fs)
function C_Stream_For (Path : String; Mode : String; Text : Boolean) return Interfaces.C_Streams.FILEs is
   pragma Unreferenced (Text);
   use type System.Address;
   C_Path : aliased constant String := Path & ASCII.NUL;
   C_Mode : aliased constant String := Mode & ASCII.NUL;
   Stream : Interfaces.C_Streams.FILEs := Interfaces.C_Streams.NULL_Stream;
   Error  : Integer := 2;
begin
   if Path /= "" and then (for all C of Path => C /= ASCII.NUL) then
      Stream := C_Fopen (C_Path'Address, C_Mode'Address);
      Error := GNAT.OS_Lib.Errno;
   end if;
   if Stream /= Interfaces.C_Streams.NULL_Stream then
      return Stream;
   elsif Error = 2 then
      raise Ada.IO_Exceptions.Name_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
   end if;
   raise Ada.IO_Exceptions.Use_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
end C_Stream_For;
