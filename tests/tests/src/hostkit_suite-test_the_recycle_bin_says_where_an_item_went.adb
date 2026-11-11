with Ada.Streams.Stream_IO;
separate (Hostkit_Suite)
procedure Test_The_Recycle_Bin_Says_Where_An_Item_Went
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Entry_Kind;
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Hostkit.Trash.Recycle_Outcome;
   use type Hostkit.Trash.Restore_Outcome;
   use type Interfaces.Integer_64;

   --  Unique per run: the Recycle Bin is the user's own and outlives the test.
   Stamp : constant String :=
     Ada.Strings.Fixed.Trim (Integer'Image (Integer (Ada.Calendar.Seconds (Ada.Calendar.Clock))), Ada.Strings.Both);

   Short_Path : constant String := Ada.Directories.Compose (Scratch, "hk-recycled-" & Stamp & ".txt");
   Recycled   : Unbounded_String;
   Info       : Unbounded_String;
   Item       : Hostkit.Trash.Recycle_Bin_Entry;

   --  The same place, whichever separators, letter case or short (8.3)
   --  names it was given in: the shell records the long form.
   function Same_Path (Left, Right : String) return Boolean is
      function Plain (Path : String) return String is
         Result : String := Ada.Characters.Handling.To_Lower (Path);
      begin
         for Char of Result loop
            if Char = '/' then
               Char := '\';
            end if;
         end loop;
         return Result;
      end Plain;

      function Split (Path : String) return Natural is
      begin
         for Index in reverse Path'Range loop
            if Path (Index) in '/' | '\' then
               return Index;
            end if;
         end loop;
         return 0;
      end Split;

      --  The folder, resolved where it still exists.
      function Folder (Path : String) return String is
         At_Split : constant Natural := Split (Path);
         Text     : constant String := (if At_Split = 0 then "" else Path (Path'First .. At_Split - 1));
         Real     : constant String := (if Text = "" then "" else Hostkit.Fs.Real_Path (Text));
      begin
         return Plain (if Real = "" then Text else Real);
      end Folder;
   begin
      return Plain (Left) = Plain (Right)
        or else (Folder (Left) = Folder (Right)
                 and then Plain (Left (Split (Left) + 1 .. Left'Last))
                            = Plain (Right (Split (Right) + 1 .. Right'Last)));
   end Same_Path;

   function Is_Present (Path : String) return Boolean is
     (Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Missing_Entry);

   --  A file of Text at Path, past any path limit.
   procedure Write_Long (Path : String; Text : String) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Hostkit.Fs.Create_Stream (File, Ada.Streams.Stream_IO.Out_File, Path);
      String'Write (Ada.Streams.Stream_IO.Stream (File), Text);
      Ada.Streams.Stream_IO.Close (File);
   end Write_Long;

   --  Recycle Path and check the answer names the item and its record.
   procedure Recycle (Path : String; What : String) is
   begin
      Assert
        (Hostkit.Trash.Move_To_Recycle_Bin (Path, Recycled, Info) = Hostkit.Trash.Recycled,
         What & " goes to the Recycle Bin");
      Assert (not Is_Present (Path), What & " is gone from where it was");
      Assert
        (Hostkit.Trash.Is_Recycled_Item (To_String (Recycled)),
         What & ": the answer is the $R item in the user's bin; was " & To_String (Recycled));
      Assert (Is_Present (To_String (Recycled)), What & " is there");
      Assert (Is_Present (To_String (Info)), What & " has its $I record beside it");
      Assert
        (Hostkit.Trash.Entry_Of (To_String (Recycled), Item)
         and then Same_Path (To_String (Item.Original_Path), Path),
         What & ": the $I record names where it came from; was " & To_String (Item.Original_Path));
      Assert (Item.Deleted_Known, What & ": and when");
   end Recycle;
begin
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Skip ("Test_The_Recycle_Bin_Says_Where_An_Item_Went", "needs the Windows Recycle Bin");
      return;
   end if;

   --  Through the shell.
   Write_File (Short_Path, "to the bin");
   Recycle (Short_Path, "a file");
   Assert (Item.Size > 0, "its size is recorded");
   Assert
     ((for some Listed of Hostkit.Trash.Recycle_Bin_Entries =>
         Same_Path (To_String (Listed.Recycled_Path), To_String (Recycled))),
      "the bin's listing holds it");
   Assert
     (Hostkit.Trash.Recycle_Bin_Folder (Scratch) /= ""
      and then Same_Path
        (Hostkit.Trash.Recycle_Bin_Folder (Scratch),
         Ada.Directories.Containing_Directory (To_String (Recycled))),
      "in the user's own folder of that drive's bin");

   Assert (Hostkit.Trash.Restore (To_String (Recycled)) = Hostkit.Trash.Restored, "Restore puts it back");
   Assert (First_Line (Short_Path) = "to the bin", "where it was, as it was");
   Assert (not Is_Present (To_String (Recycled)), "the item has left the bin");
   Assert (not Is_Present (To_String (Info)), "and so has its record");

   --  Restore never replaces; Purge deletes the item and its record.
   Recycle (Short_Path, "the file again");
   Write_File (Short_Path, "newcomer");
   Assert
     (Hostkit.Trash.Restore (To_String (Recycled)) = Hostkit.Trash.Restore_Taken,
      "a restore onto a taken name is refused");
   Assert (First_Line (Short_Path) = "newcomer", "the newcomer is untouched");
   Assert (Is_Present (To_String (Recycled)), "the item stays in the bin");
   Assert (Hostkit.Trash.Purge (To_String (Recycled)), "Purge deletes it from the bin");
   Assert (not Is_Present (To_String (Recycled)) and then not Is_Present (To_String (Info)), "item and record");
   Ada.Directories.Delete_File (Short_Path);

   --  Past the 259 characters the shell takes: renamed into the bin's
   --  folder, with a record written as the shell writes one.
   declare
      Top  : constant String := Ada.Directories.Compose (Scratch, "hk-long-" & Stamp);
      Deep : Unbounded_String := To_Unbounded_String (Top);
   begin
      while Length (Deep) <= 300 loop
         Deep := To_Unbounded_String (Hostkit.Fs.Join (To_String (Deep), [1 .. 40 => 'd']));
      end loop;
      Assert (Hostkit.Fs.Create_Path (To_String (Deep)), "a folder past MAX_PATH is made");
      declare
         Long_File : constant String := Hostkit.Fs.Join (To_String (Deep), "far.txt");
      begin
         Write_Long (Long_File, "far down");
         Assert (Long_File'Length > 300, "the file's path is past 300 characters");
         Assert (Hostkit.Trash.Can_Hold (Long_File), "the bin holds a long path on a fixed drive");

         Recycle (Long_File, "a file past MAX_PATH");
         Assert (Item.Size = 8, "its size is recorded");
         Assert (Hostkit.Trash.Restore (To_String (Recycled)) = Hostkit.Trash.Restored, "and restored");
         Assert (Is_Present (Long_File) and then not Is_Present (To_String (Info)), "to its long path");

         Recycle (Long_File, "the long file again");
         Assert (Hostkit.Trash.Purge (To_String (Recycled)), "and purged");
         Assert (not Is_Present (To_String (Recycled)), "the purged item is gone");

         --  A folder past MAX_PATH, with what it holds.
         Write_Long (Long_File, "inside");
         Recycle (To_String (Deep), "a folder past MAX_PATH");
         Assert (Item.Size = 6, "its total size is recorded");
         Assert (Hostkit.Trash.Purge (To_String (Recycled)), "and it is purged whole");
         Assert (not Is_Present (To_String (Recycled)), "the purged folder is gone");
      end;
      Assert (Hostkit.Fs.Delete_Tree_No_Follow (Top) = Hostkit.Fs.Tree_Deleted, "the fixture is removed");
   end;
end Test_The_Recycle_Bin_Says_Where_An_Item_Went;
