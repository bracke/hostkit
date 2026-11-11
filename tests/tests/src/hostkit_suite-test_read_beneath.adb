with Ada.IO_Exceptions;
separate (Hostkit_Suite)
procedure Test_Read_Beneath
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Read_Beneath_Outcome;
   Root    : constant String := Ada.Directories.Compose (Scratch, "hk-read-beneath");
   Outside : constant String := Ada.Directories.Compose (Scratch, "hk-read-beneath-outside");
   Sub     : constant String := Ada.Directories.Compose (Root, "sub");
   Held    : constant String := Ada.Directories.Compose (Root, "held");
   Away    : constant String := Ada.Directories.Compose (Root, "away");
   File_Link : constant String := Ada.Directories.Compose (Sub, "file-link");
   Text    : Unbounded_String;
   Outcome : Hostkit.Fs.Read_Beneath_Outcome;

   function Read (Path : String; Most : Natural := 1_000) return Hostkit.Fs.Read_Beneath_Outcome is
   begin
      Hostkit.Fs.Read_Beneath (Root, Path, Most, Text, Outcome);
      return Outcome;
   end Read;

   procedure Drop_Link (Path : String) is
   begin
      if Hostkit.Fs.Is_Link (Path) then
         declare
            Ignored : constant Boolean := Hostkit.Fs.Delete_Link (Path);
         begin
            null;
         end;
      end if;
   end Drop_Link;

   procedure Clean is
   begin
      Drop_Link (Away);
      Drop_Link (File_Link);
      Drop_Link (Sub);
      Delete_Tree_If_Present (Root);
      Delete_Tree_If_Present (Outside);
   end Clean;
begin
   Clean;
   Ada.Directories.Create_Path (Sub);
   Ada.Directories.Create_Path (Outside);
   Write_File (Ada.Directories.Compose (Sub, "f.txt"), "inside");
   Write_File (Ada.Directories.Compose (Outside, "f.txt"), "outside");

   declare
      First : constant Hostkit.Fs.Read_Beneath_Outcome := Read ("sub/f.txt");
   begin
      Assert (First = Hostkit.Fs.Read_Done and then Ada.Strings.Unbounded.Index (Text, "inside") = 1,
              "a file below the root is read: " & First'Image & " " & To_String (Text));
   end;
   Assert (Read ("./sub//f.txt") = Hostkit.Fs.Read_Done and then Ada.Strings.Unbounded.Index (Text, "inside") = 1,
           "empty and dot parts are skipped");
   Assert (Read ("sub/f.txt", Most => 3) = Hostkit.Fs.Read_Too_Large and then Length (Text) = 0,
           "a file larger than asked is refused");
   Assert (Read ("sub/none.txt") = Hostkit.Fs.Read_Missing, "a missing file is missing");
   Assert (Read ("none/f.txt") = Hostkit.Fs.Read_Missing, "a missing directory is missing");
   Assert (Read ("sub/f.txt/more") = Hostkit.Fs.Read_Missing, "a file taken for a directory is missing");
   Assert (Read ("sub") = Hostkit.Fs.Read_Not_File, "a directory is no file");
   Assert (Read ("sub/../sub/f.txt") = Hostkit.Fs.Read_Outside, "a climbing path is refused");
   Assert (Read ("/etc/hostname") = Hostkit.Fs.Read_Outside, "an absolute path is refused");
   Assert (Read ("") = Hostkit.Fs.Read_Outside, "an empty path is refused");

   if Hostkit.Fs.Create_Link (Outside, Away) then
      Assert (Read ("away/f.txt") = Hostkit.Fs.Read_Outside and then Length (Text) = 0,
              "a directory link on the way is not followed");
      if Hostkit.Fs.Create_Link (Ada.Directories.Compose (Outside, "f.txt"), File_Link) then
         Assert (Read ("sub/file-link") = Hostkit.Fs.Read_Outside, "a file link is not followed");
      else
         Links_Refused ("Read_Beneath, a file link");
      end if;

      --  The race a check before the read loses: the directory on the
      --  way swapped for a link out of the tree, and back, as fast as
      --  the host will, while the file below it is read again and again.
      declare
         Rounds  : constant := 10_000;
         Leaked  : Natural := 0;
         Done_In : Natural := 0;

         task Swapper;
         task body Swapper is
            --  A read holding the folder refuses a step for a moment (the
            --  point of the walk): the step is tried again, so a round is
            --  always finished and the tree is whole when the task ends.
            procedure Rename (From, To : String) is
            begin
               loop
                  begin
                     Ada.Directories.Rename (From, To);
                     return;
                  exception
                     when Ada.IO_Exceptions.Use_Error =>
                        delay 0.0;
                  end;
               end loop;
            end Rename;
         begin
            for Round in 1 .. Rounds loop
               Rename (Sub, Held);
               while not Hostkit.Fs.Create_Link (Outside, Sub) loop
                  delay 0.0;
               end loop;
               while not Hostkit.Fs.Delete_Link (Sub) loop
                  delay 0.0;
               end loop;
               Rename (Held, Sub);
            end loop;
         end Swapper;
      begin
         while not Swapper'Terminated loop
            Hostkit.Fs.Read_Beneath (Root, "sub/f.txt", 1_000, Text, Outcome);
            if Outcome = Hostkit.Fs.Read_Done then
               if Ada.Strings.Unbounded.Index (Text, "inside") = 1 then
                  Done_In := Done_In + 1;
               else
                  Leaked := Leaked + 1;
               end if;
            end if;
         end loop;
         Assert (Leaked = 0, "a read followed a link swapped in on the way:" & Leaked'Image);
         Assert (Read ("sub/f.txt") = Hostkit.Fs.Read_Done and then Ada.Strings.Unbounded.Index (Text, "inside") = 1,
                 "the file is read once the swapping stops" & Done_In'Image);
      end;
   else
      Links_Refused ("Read_Beneath, a directory link and the swap race");
   end if;
   Clean;
exception
   when others =>
      Clean;
      raise;
end Test_Read_Beneath;
