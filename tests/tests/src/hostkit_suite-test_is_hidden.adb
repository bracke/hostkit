separate (Hostkit_Suite)
procedure Test_Is_Hidden
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Root  : constant String := Hostkit.Fs.Create_Temporary_Directory ("hk-hidden");
   Plain : constant String := Ada.Directories.Compose (Root, "plain.txt");
   Dot   : constant String := Ada.Directories.Compose (Root, ".dotted");

   --  Run Program with Arguments; False when it is not on PATH or fails.
   function Run (Program : String; Arguments : GNAT.OS_Lib.Argument_List) return Boolean is
      use type GNAT.OS_Lib.String_Access;
      Found   : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path (Program);
      Success : Boolean := False;
   begin
      if Found /= null then
         GNAT.OS_Lib.Spawn (Found.all, Arguments, Success);
         GNAT.OS_Lib.Free (Found);
      end if;
      return Success;
   end Run;
begin
   begin
      Write_File (Plain, "x");
      Write_File (Dot, "x");
      Assert (not Hostkit.Fs.Is_Hidden (Plain), "an ordinary file is not hidden");
      Assert (not Hostkit.Fs.Is_Hidden (Dot), "a leading dot is the caller's rule, not a host flag");
      case Hostkit.Host.Current is
         when Hostkit.Host.MacOS =>
            declare
               Flag : aliased String := "hidden";
               Name : aliased String := Plain;
            begin
               if Run ("chflags", [Flag'Unchecked_Access, Name'Unchecked_Access]) then
                  Assert (Hostkit.Fs.Is_Hidden (Plain), "UF_HIDDEN marks the entry hidden");
               end if;
            end;
         when Hostkit.Host.Windows =>
            declare
               Flag : aliased String := "+h";
               Name : aliased String := Plain;
            begin
               if Run ("attrib", [Flag'Unchecked_Access, Name'Unchecked_Access]) then
                  Assert (Hostkit.Fs.Is_Hidden (Plain), "FILE_ATTRIBUTE_HIDDEN marks the entry hidden");
               end if;
            end;
         when others =>
            null;
      end case;
   exception
      when others =>
         Delete_Tree_If_Present (Root);
         raise;
   end;
   Delete_Tree_If_Present (Root);
end Test_Is_Hidden;
