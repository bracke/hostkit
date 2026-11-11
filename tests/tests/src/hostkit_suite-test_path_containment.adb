separate (Hostkit_Suite)
procedure Test_Path_Containment (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Sep : constant Character := Hostkit.Fs.Separator;
   function P (Parts : String) return String is
     ([for C of Parts => (if C = '|' then Sep else C)]);
begin
   Assert (Hostkit.Fs.Is_Separator ('/'), "a slash separates everywhere");
   Assert
     (Hostkit.Fs.Is_Separator ('\') = (Hostkit.Host.Current = Hostkit.Host.Windows),
      "a backslash separates on Windows only");
   Assert (Hostkit.Fs.Is_Same_Or_Inside (P ("|a|b"), P ("|a|b")), "a path is the same as itself");
   Assert (Hostkit.Fs.Is_Same_Or_Inside (P ("|a|b|c"), P ("|a|b")), "a child is inside");
   Assert (not Hostkit.Fs.Is_Same_Or_Inside (P ("|a|bc"), P ("|a|b")), "a sibling sharing a prefix is not");
   Assert (Hostkit.Fs.Is_Same_Or_Inside (P ("|a"), P ("|")), "everything is inside the root");
   Assert (not Hostkit.Fs.Is_Same_Or_Inside ("", P ("|a")), "an empty path is inside nothing");
   Assert (Hostkit.Fs.Rebase (P ("|a|b|c"), P ("|a|b"), P ("|x")) = P ("|x|c"), "a child follows its tree");
   Assert (Hostkit.Fs.Rebase (P ("|a|b"), P ("|a|b"), P ("|x")) = P ("|x"), "the tree itself moves");
   Assert (Hostkit.Fs.Rebase (P ("|a|bc"), P ("|a|b"), P ("|x")) = P ("|a|bc"), "a sibling stays");
end Test_Path_Containment;
