separate (Hostkit.Fs)
function Set_Creation_Mask
  (Value : Natural; Previous : out Natural) return Boolean
is
   Held : constant Interfaces.C.unsigned := C_Umask (Interfaces.C.unsigned (Value));
begin
   Previous := Natural (Held);
   return True;
end Set_Creation_Mask;
