separate (Hostkit_Suite)
procedure Test_Path_Text_Absolute
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Entry_Kind;
   package PT renames Hostkit.Path_Text;
   Windows : constant Boolean := Hostkit.Host.Current = Hostkit.Host.Windows;
   --  Past GNAT's Windows limits of 256 characters a component and 260 a
   --  path.
   Long    : constant String := [1 .. 300 => 'n'];

   type Case_Row is record
      Path   : Unbounded_String;
      Base   : Unbounded_String;
      Wanted : Unbounded_String;
   end record;

   type Case_Table is array (Positive range <>) of Case_Row;

   function Row (Path : String; Base : String; Wanted : String) return Case_Row is
     (To_Unbounded_String (Path), To_Unbounded_String (Base), To_Unbounded_String (Wanted));

   --  The same on every host: POSIX paths with '/', and Windows paths that
   --  start the Windows way.
   Rows : constant Case_Table :=
     [Row ("", "", ""),
      Row ("", "/a/", "/a"),
      Row ("/", "/a", "/"),
      Row ("/a/b/../c", "/x", "/a/c"),
      Row ("b/./c", "/a", "/a/b/c"),
      Row ("../c", "/a/b", "/a/c"),
      Row ("../../..", "/a", "/"),
      Row ("/..", "/a", "/"),
      Row ("a//b/", "/", "/a/b"),
      Row ("x", "/", "/x"),
      Row ("../x", "", "../x"),
      Row ("a/../..", "", ".."),
      Row ("a/..", "", "."),
      Row ("a/./b", "", "a/b"),
      Row ("a/" & Long & "/../b", "/r", "/r/a/b"),
      Row ("C:\a\..\b", "/x", "C:\b"),
      Row ("C:/a/./b", "/x", "C:/a/b"),
      Row ("C:\", "", "C:\"),
      Row ("sub\..\f.txt", "C:\dir", "C:\dir\f.txt"),
      Row ("..\..\..", "C:\a", "C:\"),
      Row ("x\" & Long & "\..", "C:\dir\", "C:\dir\x"),
      Row ("C:\" & Long & "\x\..", "", "C:\" & Long),
      Row ("\top", "C:\dir", "C:\top"),
      Row ("\top", "\\server\share\dir", "\\server\share\top"),
      Row ("..", "\\server\share\dir", "\\server\share"),
      Row ("..\..", "\\server\share", "\\server\share"),
      Row ("\\server\share\", "", "\\server\share"),
      Row ("C:x", "C:\dir", "C:\dir\x"),
      Row ("c:x", "C:\dir", "C:\dir\x"),
      Row ("D:x", "C:\dir", "D:\x"),
      Row ("\\?\C:\a\..\b", "/x", "\\?\C:\a\..\b"),
      Row ("..\b", "\\?\C:\a", "\\?\C:\a\..\b"),
      Row ("\\.\pipe\x", "", "\\.\pipe\x")];
begin
   for Item of Rows loop
      declare
         Path   : constant String := To_String (Item.Path);
         Base   : constant String := To_String (Item.Base);
         Wanted : constant String := To_String (Item.Wanted);
         What   : constant String :=
           """" & Path (Path'First .. Path'First + Natural'Min (Path'Length, 24) - 1) & """ against """
           & Base (Base'First .. Base'First + Natural'Min (Base'Length, 24) - 1) & """";
      begin
         Assert (PT.Absolute (Path, Base) = Wanted, What & " is absolute and resolved");
      end;
   end loop;

   declare
      --  An answer indexed from 1 whatever the argument's bounds.
      Shifted : constant String (11 .. 16) := "ab/../";
   begin
      Assert (PT.Absolute (Shifted, "/r")'First = 1, "an absolute path is indexed from 1");
      Assert (PT.Absolute (Shifted, "/r") = "/r", "whatever its argument's bounds");
   end;

   --  A link is not followed: "link/.." is the folder holding the link.
   Assert (PT.Absolute ("link/..", "/a") = "/a", "dots are resolved from the text alone");

   --  The process's own folder, however long, is a folder that is there.
   declare
      Here : constant String := Hostkit.Fs.Current_Directory;
   begin
      Assert (Here /= "", "the current directory is answered");
      Assert (PT.Root_Length (Here) > 0, "and is absolute");
      Assert (Hostkit.Fs.Kind_Of (Here) = Hostkit.Fs.Directory_Entry, "and is a directory");
      Assert (PT.Absolute (".", Here) = PT.Absolute (Here, ""), "a relative path is read from it");
   end;

   --  A backslash separates only on Windows or in a Windows path: in a
   --  POSIX one it is part of a name.
   if Windows then
      Assert (PT.Absolute ("a\..\b", "C:/x") = "C:/x/b", "a backslash separates on Windows");
      Assert (PT.Absolute ("x", "") = "x", "a relative name stays itself");
   else
      Assert (PT.Absolute ("a\..\b", "/x") = "/x/a\..\b", "a POSIX name may hold a backslash");
      Assert (PT.Absolute ("C:x", "/home") = "/home/C:x", "and a colon");
   end if;
end Test_Path_Text_Absolute;
