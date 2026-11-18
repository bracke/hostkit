separate (Hostkit_Suite)
procedure Test_Windows_Stored_Spelling
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package WP renames Hostkit.Windows_Paths;

   --  A volume holding C:\Users\Me\Documents, C:\Program Files (short name
   --  PROGRA~1) and a junction C:\Users\Me\Link: what a listing gives back
   --  for each name it is asked about, matched without regard to case.
   function Listed (Directory : String; Name : String) return String is
      function Lower (Text : String) return String renames Ada.Characters.Handling.To_Lower;
      Key : constant String := Lower (Directory) & "|" & Lower (Name);
   begin
      if Key = "c:\|users" then
         return "Users";
      elsif Key = "c:\users|me" then
         return "Me";
      elsif Key = "c:\users\me|documents" then
         return "Documents";
      elsif Key = "c:\users\me|link" then
         return "Link";
      elsif Key = "c:\|progra~1" or else Key = "c:\|program files" then
         return "Program Files";
      elsif Key = "\\server\share|reports" then
         return "Reports";
      end if;
      return "";
   end Listed;

   function Spelled (Path : String) return String is (WP.Stored_Form (Path, Listed'Access));

   --  A macOS volume that folds case, holding /Users/Me/Notes and a link
   --  /Users/Me/Link: the name each entry is stored under, not followed.
   function Stored (Entry_Path : String) return String is
      Key : constant String := Ada.Characters.Handling.To_Lower (Entry_Path);
   begin
      if Key = "/users" then
         return "Users";
      elsif Key = "/users/me" then
         return "Me";
      elsif Key = "/users/me/notes" then
         return "Notes";
      elsif Key = "/users/me/link" then
         return "Link";
      end if;
      return "";
   end Stored;

   function Posix (Path : String) return String is (Hostkit.Path_Text.Posix_Stored_Form (Path, Stored'Access));
begin
   Assert (Spelled ("c:\users\me\documents") = "C:\Users\Me\Documents",
           "a path typed in lower case takes the stored case: " & Spelled ("c:\users\me\documents"));
   Assert (Spelled ("C:/Users/Me/Documents") = "C:\Users\Me\Documents",
           "forward slashes read as separators: " & Spelled ("C:/Users/Me/Documents"));
   Assert (Spelled ("C:\PROGRA~1") = "C:\Program Files",
           "an 8.3 short name takes its long name: " & Spelled ("C:\PROGRA~1"));
   Assert (Spelled ("c:\Users\\me\") = "C:\Users\Me",
           "a doubled or trailing separator is dropped: " & Spelled ("c:\Users\\me\"));
   Assert (Spelled ("c:\users\me\link\inside") = "C:\Users\Me\Link\inside",
           "a junction keeps its own name, and what lies past an unlisted name stays as typed: "
           & Spelled ("c:\users\me\link\inside"));
   Assert (Spelled ("c:\users\nobody\documents") = "C:\Users\nobody\documents",
           "after a name the volume does not list, the rest stays as typed: "
           & Spelled ("c:\users\nobody\documents"));
   Assert (Spelled ("c:") = "C:\" and then Spelled ("d:\") = "D:\", "a drive root is its letter, upper case");
   Assert (Spelled ("\\server\share\reports") = "\\server\share\Reports",
           "a share keeps its server and share as typed, and spells what lies inside");
   Assert (Spelled ("c:\users\..\users") = "C:\Users\..\users",
           "a dot component is not looked up, nor anything after it: " & Spelled ("c:\users\..\users"));
   Assert (Spelled ("c:\us*") = "C:\us*", "a wildcard is never looked up");
   Assert (Spelled ("users\me") = "users\me", "a relative path is left as it is");
   Assert (Spelled ("\\?\c:\users") = "\\?\c:\users", "a prefixed path is left as it is");
   Assert (Spelled ("\\server") = "\\server", "a server with no share is left as it is");

   --  The POSIX rule macOS spells by: each component as stored, the rest
   --  as typed once one is not answered for.
   Assert (Posix ("/users/me/notes") = "/Users/Me/Notes",
           "a POSIX path takes each component's stored case: " & Posix ("/users/me/notes"));
   Assert (Posix ("//users//me/") = "/Users/Me", "a doubled or trailing '/' is dropped: " & Posix ("//users//me/"));
   Assert (Posix ("/users/nobody/notes") = "/Users/nobody/notes",
           "after a component not answered for, the rest stays as typed: " & Posix ("/users/nobody/notes"));
   Assert (Posix ("/users/me/link/inside") = "/Users/Me/Link/inside",
           "a link keeps its own name: " & Posix ("/users/me/link/inside"));
   Assert (Posix ("/users/../users") = "/Users/../users",
           "a dot component is not looked up, nor anything after it: " & Posix ("/users/../users"));
   Assert (Posix ("/") = "/" and then Posix ("users/me") = "users/me",
           "the root stays the root, and a relative path is left as it is");

   --  Linux stores one spelling already.
   if Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Linux) then
      Assert (Hostkit.Fs.Stored_Spelling ("/tmp/X/../y") = "/tmp/X/../y", "a Linux path is left as it is");
   end if;
end Test_Windows_Stored_Spelling;
