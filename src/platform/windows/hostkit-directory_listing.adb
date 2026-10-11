with Ada.Directories;

--  No listing that records kinds here: every entry Unknown, for the caller
--  to ask of the entry itself.
package body Hostkit.Directory_Listing is

   function List (Path : String; Entries : out Entry_Vectors.Vector) return Boolean is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
   begin
      Entries.Clear;
      Ada.Directories.Start_Search (Search, Path, "");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name /= "." and then Name /= ".." then
               Entries.Append (Listed_Entry'(Length => Name'Length, Kind => Unknown, Name => Name));
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      return True;
   exception
      when others =>
         return False;
   end List;

end Hostkit.Directory_Listing;
