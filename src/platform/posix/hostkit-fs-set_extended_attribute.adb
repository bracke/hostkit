separate (Hostkit.Fs)
function Set_Extended_Attribute
  (Path  : String;
   Name  : String;
   Value : Ada.Streams.Stream_Element_Array) return Boolean
is
   function C_Setxattr
     (Path  : Interfaces.C.Strings.chars_ptr;
      Name  : Interfaces.C.Strings.chars_ptr;
      Value : System.Address;
      Size  : Interfaces.C.size_t;
      Flags : Interfaces.C.int) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "setxattr";

   C_Path : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Path);
   C_Name : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Name);
   Buffer : Ada.Streams.Stream_Element_Array := Value;
   Status : Interfaces.C.int;
begin
   Status :=
     C_Setxattr
       (C_Path, C_Name, Buffer'Address,
        Interfaces.C.size_t (Value'Length), 0);
   Interfaces.C.Strings.Free (C_Path);
   Interfaces.C.Strings.Free (C_Name);
   return Status = 0;
exception
   when others =>
      return False;
end Set_Extended_Attribute;
