separate (Hostkit.Fs)
function Read_Link_Target
  (Path   : String;
   Target : out Ada.Strings.Unbounded.Unbounded_String)
   return Boolean
is
   use type Interfaces.C.long;

   function C_Readlink
     (Path : Interfaces.C.Strings.chars_ptr;
      Buf  : System.Address;
      Size : Interfaces.C.size_t)
      return Interfaces.C.long
     with Import => True, Convention => C, External_Name => "readlink";

   C_Path : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Path);
   Buffer : Interfaces.C.char_array (0 .. 4095);
   Count  : Interfaces.C.long;
begin
   Target := Ada.Strings.Unbounded.Null_Unbounded_String;
   Count := C_Readlink (C_Path, Buffer'Address, 4096);
   Interfaces.C.Strings.Free (C_Path);
   if Count <= 0 then
      return False;
   end if;
   declare
      Result : String (1 .. Natural (Count));
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Character'Val
             (Interfaces.C.char'Pos
                (Buffer (Interfaces.C.size_t (Index - 1))));
      end loop;
      Target := Ada.Strings.Unbounded.To_Unbounded_String (Result);
   end;
   return True;
exception
   when others =>
      return False;
end Read_Link_Target;
