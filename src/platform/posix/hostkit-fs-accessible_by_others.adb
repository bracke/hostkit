separate (Hostkit.Fs)
function Accessible_By_Others (Path : String) return Boolean is
begin
   return Exposed (Path, Ada.Directories.Ordinary_File);
end Accessible_By_Others;
