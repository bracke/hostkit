separate (Hostkit.Fs)
function Present (Path : Interfaces.C.Strings.chars_ptr) return Boolean is
   use type Interfaces.C.long;
   Buffer : Interfaces.C.char_array (1 .. 1);
begin
   return C_Readlink (Path, Buffer, 1) >= 0 or else C_Access (Path, 0) = 0;
end Present;
