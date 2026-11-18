separate (Hostkit.Fs)
function Is_Link (Path : String) return Boolean is
begin
   return GNAT.OS_Lib.Is_Symbolic_Link (Path);
exception
   when others =>
      return False;
end Is_Link;
