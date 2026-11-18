separate (Hostkit.Fs)
function Replace_File
  (Source : String;
   Target : String)
   return Boolean
is
   function C_Rename
     (Old_Path : Interfaces.C.Strings.chars_ptr;
      New_Path : Interfaces.C.Strings.chars_ptr)
      return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "rename";

   C_Source : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Source);
   C_Target : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Target);
   Status   : Interfaces.C.int;
begin
   Status := C_Rename (C_Source, C_Target);
   Interfaces.C.Strings.Free (C_Source);
   Interfaces.C.Strings.Free (C_Target);
   return Status = 0;
exception
   when others =>
      return False;
end Replace_File;
