separate (Hostkit.Mounts)
--  This host keeps no mount table (volumes are found by their folders: drive
--  letters, /Volumes): the list is empty.
function Table return Mount_Vectors.Vector is
begin
   return Mount_Vectors.Empty_Vector;
end Table;
