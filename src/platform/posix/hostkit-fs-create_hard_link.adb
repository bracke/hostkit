separate (Hostkit.Fs)
function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is
   function C_Link
     (Old_Path : Interfaces.C.Strings.chars_ptr;
      New_Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "link";

   C_Target : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Target);
   C_Link_P : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Link_Path);
   Status   : Interfaces.C.int;
begin
   Status := C_Link (C_Target, C_Link_P);
   Interfaces.C.Strings.Free (C_Target);
   Interfaces.C.Strings.Free (C_Link_P);
   return Status = 0;
exception
   when others =>
      return False;
end Create_Hard_Link;
