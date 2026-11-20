with Hostkit.Metadata.Private_By_Mode;

separate (Hostkit.Metadata)
function Private_To_Current_User (Path : String) return Boolean is
begin
   --  The owner, mode and link rule alone: Linux reads no ACL here.
   return Hostkit.Metadata.Private_By_Mode (Path);
end Private_To_Current_User;
