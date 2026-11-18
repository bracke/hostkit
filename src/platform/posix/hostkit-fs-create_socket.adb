separate (Hostkit.Fs)
function Create_Socket (Path : String; Mode : Natural) return Boolean is
   function C_Socket (Domain, Kind, Protocol : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "socket";

   function C_Bind (FD : C_Int; Addr : System.Address; Len : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "bind";

   function C_Close (FD : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "close";

   function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
     return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "chmod";

   FD     : C_Int;
   Addr   : aliased Sockaddr_Un;
   C_Path : Interfaces.C.Strings.chars_ptr;
   Status : C_Int;
begin
   if Path'Length = 0 or else Path'Length > 107 then
      return False;
   end if;

   FD := C_Socket (AF_UNIX, SOCK_STREAM, 0);
   if FD < 0 then
      return False;
   end if;

   Addr.Family := Interfaces.C.short (AF_UNIX);
   for I in Path'Range loop
      Addr.Path (Interfaces.C.size_t (I - Path'First)) :=
        Interfaces.C.To_C (Path (I));
   end loop;

   Status := C_Bind (FD, Addr'Address, Sockaddr_Un'Size / 8);
   declare
      Ignored : constant C_Int := C_Close (FD);
   begin
      pragma Unreferenced (Ignored);
   end;

   if Status /= 0 then
      return False;
   end if;

   C_Path := Interfaces.C.Strings.New_String (Path);
   Status := C_Chmod (C_Path, Interfaces.C.int (Mode));
   Interfaces.C.Strings.Free (C_Path);
   return Status = 0;
exception
   when others =>
      return False;
end Create_Socket;
