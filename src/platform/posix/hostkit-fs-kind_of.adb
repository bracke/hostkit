separate (Hostkit.Fs)
function Kind_Of (Path : String) return Entry_Kind is
begin
   if Path = "" or else not Ada.Directories.Exists (Path) then
      return Missing_Entry;
   end if;
   case Ada.Directories.Kind (Path) is
      when Ada.Directories.Directory =>
         return Directory_Entry;
      when Ada.Directories.Ordinary_File =>
         return Ordinary_File_Entry;
      when Ada.Directories.Special_File =>
         return Special_File_Entry;
   end case;
exception
   when others =>
      return Missing_Entry;
end Kind_Of;
