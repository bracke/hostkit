separate (Hostkit_Suite)
procedure Test_Path_Text_Roots_Leaves_And_Parents
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package PT renames Hostkit.Path_Text;
   Windows : constant Boolean := Hostkit.Host.Current = Hostkit.Host.Windows;
   --  Past GNAT's Windows limit of 256 characters a component.
   Long    : constant String := [1 .. 300 => 'n'];

   type Case_Row is record
      Path   : Unbounded_String;
      Root   : Natural;
      Leaf   : Unbounded_String;
      Parent : Unbounded_String;
   end record;

   type Case_Table is array (Positive range <>) of Case_Row;

   function Row (Path : String; Root : Natural; Leaf : String; Parent : String) return Case_Row is
     (To_Unbounded_String (Path), Root, To_Unbounded_String (Leaf), To_Unbounded_String (Parent));

   --  The same on every host: POSIX paths with '/', and Windows paths that
   --  start the Windows way.
   Rows : constant Case_Table :=
     [Row ("", 0, "", ""),
      Row ("/", 1, "", ""),
      Row ("/x", 1, "x", "/"),
      Row ("/a/b", 1, "b", "/a"),
      Row ("/a/b/", 1, "b", "/a"),
      Row ("/a//b", 1, "b", "/a"),
      Row ("a/b", 0, "b", "a"),
      Row ("name", 0, "name", ""),
      Row ("/a/" & Long, 1, Long, "/a"),
      Row ("C:", 2, "", ""),
      Row ("C:\", 3, "", ""),
      Row ("C:/", 3, "", ""),
      Row ("C:\dir", 3, "dir", "C:\"),
      Row ("C:/dir/sub", 3, "sub", "C:/dir"),
      Row ("C:\dir\" & Long, 3, Long, "C:\dir"),
      Row ("C:\" & Long & "\x", 3, "x", "C:\" & Long),
      Row ("\\server\share", 14, "", ""),
      Row ("\\server\share\", 14, "", ""),
      Row ("\\server\share\dir", 14, "dir", "\\server\share"),
      Row ("\\server\share\a\b", 14, "b", "\\server\share\a"),
      Row ("\\server\share\" & Long, 14, Long, "\\server\share"),
      Row ("\\server\", 9, "", ""),
      Row ("\\server", 8, "", ""),
      Row ("\\?\C:\", 7, "", ""),
      Row ("\\?\C:\dir\" & Long, 7, Long, "\\?\C:\dir"),
      Row ("\\?\C:\" & Long, 7, Long, "\\?\C:\"),
      Row ("\\?\UNC\server\share", 20, "", ""),
      Row ("\\?\UNC\server\share\dir", 20, "dir", "\\?\UNC\server\share"),
      Row ("\\?\unc\server\share\dir", 20, "dir", "\\?\unc\server\share")];
begin
   for Item of Rows loop
      declare
         Path : constant String := To_String (Item.Path);
         What : constant String := """" & Path (Path'First .. Path'First + Natural'Min (Path'Length, 24) - 1) & """";
      begin
         Assert (PT.Root_Length (Path) = Item.Root, "the root of " & What & " is" & Item.Root'Image & " long");
         Assert (PT.Leaf (Path) = To_String (Item.Leaf), "the leaf of " & What);
         Assert (PT.Parent (Path) = To_String (Item.Parent), "the parent of " & What);
      end;
   end loop;

   declare
      --  Answers indexed from 1 whatever the argument's bounds, as
      --  Ada.Directories' are.
      Shifted : constant String (11 .. 16) := "/ab/cd";
   begin
      Assert (PT.Leaf (Shifted)'First = 1 and then PT.Leaf (Shifted) = "cd", "a leaf is indexed from 1");
      Assert (PT.Parent (Shifted)'First = 1 and then PT.Parent (Shifted) = "/ab", "and so is a parent");
   end;

   --  Two slashes are a share only on Windows: on POSIX "//usr/lib" is
   --  "/usr/lib", and a backslash in a POSIX path is part of a name.
   if Windows then
      Assert (PT.Root_Length ("//server/share/x") = 14, "slashes spell a share on Windows");
      Assert (PT.Parent ("//server/share/x") = "//server/share", "and its folder's parent is the share");
      Assert (PT.Parent ("/a\b") = "/a", "a backslash separates on Windows");
   else
      Assert (PT.Root_Length ("//usr/lib") = 1, "two slashes are the POSIX root");
      Assert (PT.Parent ("//usr/lib") = "//usr", "under which usr is a folder");
      Assert (PT.Leaf ("/a\b") = "a\b", "a POSIX name may hold a backslash");
      Assert (PT.Parent ("/a\b") = "/", "and is one component");
   end if;
end Test_Path_Text_Roots_Leaves_And_Parents;
