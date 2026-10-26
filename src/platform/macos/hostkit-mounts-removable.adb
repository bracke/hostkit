separate (Hostkit.Mounts)
--  This host does not say which disks are removable through a mount's source.
function Removable (Source : String; Known : out Boolean) return Boolean is
   pragma Unreferenced (Source);
begin
   Known := False;
   return False;
end Removable;
