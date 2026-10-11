with Ada.Containers.Indefinite_Vectors;

--  The entries of a directory, each with its kind as the directory itself
--  records it -- without following a link, and without a call on each
--  entry to ask. A program walking a tree asked the host twice an entry,
--  whether it was a link and what it was, where the listing already said.
package Hostkit.Directory_Listing is

   --  What an entry is. Unknown where the filesystem does not record it
   --  in the directory, or the host has no such listing: the caller asks
   --  the entry itself.
   type Entry_Kind is (Regular_File, Directory, Symbolic_Link, Other, Unknown);

   type Listed_Entry (Length : Natural) is record
      Kind : Entry_Kind;
      Name : String (1 .. Length);
   end record;

   package Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Listed_Entry);

   --  List a directory: its entries, . and .. left out, in the order the
   --  directory gives them.
   --
   --  @param Path The directory.
   --  @param Entries Its entries.
   --  @return False where it could not be listed.
   function List (Path : String; Entries : out Entry_Vectors.Vector) return Boolean;

end Hostkit.Directory_Listing;
