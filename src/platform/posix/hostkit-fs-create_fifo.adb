separate (Hostkit.Fs)
function Create_FIFO (Path : String; Mode : Natural) return Boolean is
   function C_Mkfifo
     (Path : Interfaces.C.Strings.chars_ptr;
      Mode : Interfaces.C.unsigned) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "mkfifo";

   C_Path : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Path);
   Status : Interfaces.C.int;
begin
   Status := C_Mkfifo (C_Path, Interfaces.C.unsigned (Mode));
   Interfaces.C.Strings.Free (C_Path);
   return Status = 0;
exception
   when others =>
      return False;
end Create_FIFO;
