separate (Hostkit_Suite)
procedure Test_Parent_Watch
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Process.Presence;
   Record_At : constant String := Ada.Directories.Compose (Scratch, "hk-watched.txt");
   Arguments : Hostkit.String_Vectors.Vector;
   Status    : Integer;
begin
   if Ada.Directories.Exists (Record_At) then
      Ada.Directories.Delete_File (Record_At);
   end if;
   Arguments.Append (Ada.Strings.Unbounded.To_Unbounded_String (Record_At));
   Assert (Hostkit.Process.Run (Companion ("orphaner"), Arguments, Status), "the orphaner ran");
   Assert (Ada.Directories.Exists (Record_At), "the watched child wrote its record");
   declare
      File     : Ada.Text_IO.File_Type;
      Pid      : Integer;
      Arranged : Boolean;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Record_At);
      Pid := Integer'Value (Ada.Text_IO.Get_Line (File));
      Arranged := Ada.Text_IO.Get_Line (File) = "arranged";
      Ada.Text_IO.Close (File);
      Ada.Directories.Delete_File (Record_At);
      Assert
        (Arranged or else Hostkit.Host.Current = Hostkit.Host.Unsupported,
         "every supported host can end a child with its parent");
      if Arranged then
         --  Its parent has gone: within a few seconds, so has it.
         for Try in 1 .. 100 loop
            exit when Hostkit.Process.Presence_Of (Pid) = Hostkit.Process.Absent;
            delay 0.05;
         end loop;
         declare
            Left : constant Boolean := Hostkit.Process.Presence_Of (Pid) = Hostkit.Process.Absent;
         begin
            if not Left then
               declare
                  Ignored : constant Boolean := Hostkit.Process.Request_Stop (Pid);
               begin
                  null;
               end;
            end if;
            Assert (Left, "an orphan that asked to end with its parent was still running");
         end;
      else
         declare
            Ignored : constant Boolean := Hostkit.Process.Request_Stop (Pid);
         begin
            null;
         end;
      end if;
   end;
end Test_Parent_Watch;
