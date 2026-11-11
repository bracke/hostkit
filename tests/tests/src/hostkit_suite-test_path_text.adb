separate (Hostkit_Suite)
procedure Test_Path_Text
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package PT renames Hostkit.Path_Text;
begin
   Assert (PT.Is_Separator_In ("C:\a", '\'), "a Windows path's backslash separates, on any host");
   Assert (PT.Is_Separator_In ("/a/b", '/'), "a slash always separates");
   Assert
     (PT.Is_Separator_In ("/a\b", '\') = (Hostkit.Host.Current = Hostkit.Host.Windows),
      "a POSIX path's backslash is part of a name except on Windows");
   Assert (PT.Share_Root_Last ("\\server\share\dir") = 15, "a share's root ends with its closing separator");
   Assert (PT.Share_Root_Last ("\\server\share") = 14, "or with its name when nothing follows");
   Assert (PT.Share_Root_Last ("//server/share/x") = 15, "slashes spell a share too");
   Assert (PT.Share_Root_Last ("\\server\") = 0, "a server alone names no share");
   Assert (PT.Share_Root_Last ("\\server") = 0, "nor does a bare server name");
   Assert (PT.Share_Root_Last ("\server\share") = 0, "one leading separator is not a share");
   Assert (PT.Share_Root_Last ("C:\share\x") = 0, "nor is a drive path");
end Test_Path_Text;
