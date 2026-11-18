separate (Hostkit.Fs)
function Owner_Bit (Path : String; Bit : C_U16) return Boolean is
begin
   return (Stat_Entry (Path, True, Want_Mode).Mode and Bit) /= 0;
exception
   when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
      return False;
end Owner_Bit;
