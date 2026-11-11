separate (Hostkit_Suite)
procedure Test_Move_No_Replace_Outcome
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   use type Hostkit.Fs.Move_Outcome;

   pragma Unreferenced (T);

   Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("hk-move");
   Source : constant String := Ada.Directories.Compose (Root, "source.txt");
   Target : constant String := Ada.Directories.Compose (Root, "target.txt");
   Taken  : constant String := Ada.Directories.Compose (Root, "taken.txt");
   Absent : constant String := Ada.Directories.Compose (Root, "absent.txt");
begin
   begin
      Write_File (Source, "payload");
      Write_File (Taken, "keep");
      Assert
        (Hostkit.Fs.Move_No_Replace_Outcome (Absent, Target) = Hostkit.Fs.Move_Refused,
         "a missing source is refused, not offered to a copy fallback");
      Assert
        (Hostkit.Fs.Move_No_Replace_Outcome (Source, Taken) = Hostkit.Fs.Move_Refused,
         "an occupied target is refused, not offered to a copy fallback");
      Assert (Ada.Directories.Exists (Source), "a refused move leaves the source");
      Assert
        (Hostkit.Fs.Move_No_Replace_Outcome (Source, Target) = Hostkit.Fs.Moved,
         "a free target on the same filesystem is moved");
      Assert
        (Ada.Directories.Exists (Target) and then not Ada.Directories.Exists (Source),
         "the moved entry is at the target only");
   exception
      when others =>
         Delete_Tree_If_Present (Root);
         raise;
   end;

   Delete_Tree_If_Present (Root);
end Test_Move_No_Replace_Outcome;
