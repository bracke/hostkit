separate (Hostkit.Fs)
function Create_Link
  (Target    : String;
   Link_Path : String)
   return Boolean
is
   use type Interfaces.C.Strings.chars_ptr;
   C_Target : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Target);
   C_Link   : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Link_Path);
   Status   : Interfaces.C.int;
begin
   Status := Symlink (C_Target, C_Link);
   Interfaces.C.Strings.Free (C_Target);
   Interfaces.C.Strings.Free (C_Link);
   return Status = 0;
exception
   when others =>
      if C_Target /= Interfaces.C.Strings.Null_Ptr then
         Interfaces.C.Strings.Free (C_Target);
      end if;
      if C_Link /= Interfaces.C.Strings.Null_Ptr then
         Interfaces.C.Strings.Free (C_Link);
      end if;
      return False;
end Create_Link;
