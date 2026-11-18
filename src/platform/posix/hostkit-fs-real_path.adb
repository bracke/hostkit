separate (Hostkit.Fs)
function Real_Path (Path : String) return String is
   use type System.Address;

   function C_Realpath
     (Path     : Interfaces.C.Strings.chars_ptr;
      Resolved : System.Address)
      return System.Address
     with Import => True, Convention => C, External_Name => "realpath";

   C_Path : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Path);
   Buffer : Interfaces.C.char_array (0 .. 4095) := [others => Interfaces.C.nul];
   Result : System.Address;
begin
   Result := C_Realpath (C_Path, Buffer'Address);
   Interfaces.C.Strings.Free (C_Path);
   if Result = System.Null_Address then
      return "";
   end if;
   return Interfaces.C.To_Ada (Buffer, Trim_Nul => True);
exception
   when others =>
      return "";
end Real_Path;
