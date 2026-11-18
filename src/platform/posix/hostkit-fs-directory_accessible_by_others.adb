separate (Hostkit.Fs)
function Directory_Accessible_By_Others (Path : String) return Boolean is
begin
   return Exposed (Path, Ada.Directories.Directory);
end Directory_Accessible_By_Others;
