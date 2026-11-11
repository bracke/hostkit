with Hostkit.Path_Text;

--  The same on every host: what differs, making one directory and asking
--  what an entry is, is each host's Create_Directory and Kind_Of.
separate (Hostkit.Fs)
function Create_Path (Path : String) return Boolean is
   Parent : constant String := Hostkit.Path_Text.Parent (Path);
begin
   if Path = "" then
      return False;
   elsif Kind_Of (Path) = Directory_Entry then
      return True;
   elsif Parent /= "" and then Kind_Of (Parent) /= Directory_Entry and then not Create_Path (Parent) then
      return False;
   end if;
   --  Someone else may have made it meanwhile; a directory is what was asked.
   return Create_Directory (Path) or else Kind_Of (Path) = Directory_Entry;
end Create_Path;
