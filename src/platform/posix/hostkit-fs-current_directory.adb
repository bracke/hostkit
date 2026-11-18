separate (Hostkit.Fs)
function Current_Directory return String is
   use type Interfaces.C.Strings.chars_ptr;
   function C_Getcwd (Buffer : System.Address; Size : Interfaces.C.size_t) return Interfaces.C.Strings.chars_ptr
     with Import => True, Convention => C, External_Name => "getcwd";
   procedure C_Free (Item : Interfaces.C.Strings.chars_ptr)
     with Import => True, Convention => C, External_Name => "free";
   Buffer : constant Interfaces.C.Strings.chars_ptr := C_Getcwd (System.Null_Address, 0);
begin
   if Buffer = Interfaces.C.Strings.Null_Ptr then
      return "";
   end if;
   declare
      Result : constant String := Interfaces.C.Strings.Value (Buffer);
   begin
      C_Free (Buffer);
      return Result;
   end;
end Current_Directory;
