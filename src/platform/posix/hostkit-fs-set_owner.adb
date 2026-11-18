separate (Hostkit.Fs)
function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean is
   function C_Chown
     (Path : Interfaces.C.Strings.chars_ptr;
      UID  : Interfaces.C.int;
      GID  : Interfaces.C.int) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "chown";

   C_Path : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Path);
   Status : Interfaces.C.int;
begin
   Status :=
     C_Chown (C_Path, Interfaces.C.int (User), Interfaces.C.int (Group));
   Interfaces.C.Strings.Free (C_Path);
   return Status = 0;
exception
   when others =>
      return False;
end Set_Owner;
