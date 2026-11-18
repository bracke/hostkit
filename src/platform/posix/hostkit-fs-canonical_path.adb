separate (Hostkit.Fs)
--  realpath(3) answers only for a path that is all there: Real_Path itself.
function Canonical_Path (Path : String) return String is
begin
   return Real_Path (Path);
end Canonical_Path;
