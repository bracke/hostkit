separate (Hostkit.Fs)
function Creation_Mask (Value : out Natural) return Boolean is
   Held : constant Interfaces.C.unsigned := C_Umask (0);
   Back : constant Interfaces.C.unsigned := C_Umask (Held);
begin
   pragma Unreferenced (Back);
   Value := Natural (Held);
   return True;
end Creation_Mask;
