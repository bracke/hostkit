separate (Hostkit_Suite)
procedure Test_Joining_Paths_Uses_One_Separator
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Slash : constant Character := Hostkit.Fs.Separator;
begin
   Assert (Hostkit.Fs.Join ("a", "b") = "a" & Slash & "b",
           "two segments were not joined by one separator: "
           & Hostkit.Fs.Join ("a", "b"));

   --  A base that already ends in a separator does not get another, and
   --  either spelling counts as one: a path may have come from somewhere
   --  that writes them the other way.
   Assert (Hostkit.Fs.Join ("a/", "b") = "a/b",
           "a trailing slash gained a second separator: "
           & Hostkit.Fs.Join ("a/", "b"));
   Assert (Hostkit.Fs.Join ("a\", "b") = "a\b",
           "a trailing backslash gained a second separator: "
           & Hostkit.Fs.Join ("a\", "b"));

   --  An empty side is the other side, so a caller need not test for it
   --  before every join.
   Assert (Hostkit.Fs.Join ("", "b") = "b", "an empty base changed the part");
   Assert (Hostkit.Fs.Join ("a", "") = "a", "an empty part changed the base");
   Assert (Hostkit.Fs.Join ("", "") = "", "two empty sides produced something");

   --  Chaining is how a multi-segment tail is built, since that is what
   --  Compose cannot do.
   Assert (Hostkit.Fs.Join (Hostkit.Fs.Join ("a", "b"), "c")
           = "a" & Slash & "b" & Slash & "c",
           "chaining did not build a three-segment path");

   Assert (Slash = '/' or else Slash = '\',
           "the separator is neither of the two a host writes");
end Test_Joining_Paths_Uses_One_Separator;
