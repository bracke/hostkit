separate (Hostkit_Suite)
procedure Test_Windows_Long_Path_Form
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package WP renames Hostkit.Windows_Paths;

   --  A name of N characters, so a few of them pass the threshold.
   function Segment (N : Positive) return String is [1 .. N => 'd'];

   Tail : constant String := Segment (120) & "\" & Segment (130);
begin
   Assert (WP.Long_Path_Form ("C:\short") = "C:\short", "a short path is left as it is");
   Assert
     (WP.Long_Path_Form ("C:\" & Tail) = "\\?\C:\" & Tail,
      "a long drive path gets the \\?\ prefix");
   Assert
     (WP.Long_Path_Form ("C:/" & Segment (120) & "/" & Segment (130)) = "\\?\C:\" & Tail,
      "slashes become backslashes, which the prefixed form no longer translates");
   Assert
     (WP.Long_Path_Form ("\\server\share\" & Tail) = "\\?\UNC\server\share\" & Tail,
      "a long share path gets the \\?\UNC\ prefix");
   Assert
     (WP.Long_Path_Form ("\\?\C:\" & Tail) = "\\?\C:\" & Tail,
      "a path that is already prefixed is not prefixed twice");
   Assert
     (WP.Long_Path_Form ("C:\" & Segment (120) & "\..\" & Segment (130))
        = "C:\" & Segment (120) & "\..\" & Segment (130),
      "a path with a .. component keeps the normalisation the prefix would turn off");
   Assert
     (WP.Long_Path_Form (Tail) = Tail,
      "a relative path is left for the API to resolve");
   Assert
     (WP.Native ("C:\a") = "C:\a" & Wide_Character'Val (0),
      "the wide form is the UTF-16 text with a terminating NUL");
end Test_Windows_Long_Path_Form;
