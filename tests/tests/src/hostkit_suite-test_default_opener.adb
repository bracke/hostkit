separate (Hostkit_Suite)
procedure Test_Default_Opener (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Program   : Ada.Strings.Unbounded.Unbounded_String;
   Arguments : Hostkit.String_Vectors.Vector;
   Found     : constant Boolean := Hostkit.Process.Default_Opener ("text/plain", "<FILE>", Program, Arguments);
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (Found, "Windows always has a default opener");
   end if;
   if Found then
      Assert (Ada.Strings.Unbounded.Length (Program) > 0, "it names a program");
      Assert (not Arguments.Is_Empty
              and then Ada.Strings.Unbounded.To_String (Arguments.Last_Element) = "<FILE>",
              "and the file, by the caller's token, last");
   else
      Assert (Ada.Strings.Unbounded.Length (Program) = 0 and then Arguments.Is_Empty,
              "no opener names no program");
   end if;
end Test_Default_Opener;
