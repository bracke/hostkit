separate (Hostkit.Mounts)
function Filesystem_Root return String is
begin
   --  "/" is drive-relative here; the drives are the roots.
   return "";
end Filesystem_Root;
