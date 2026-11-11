separate (Hostkit_Suite)
procedure Test_Writes_Are_Made_Durable (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   use type Hostkit.Durability.Outcome;
   Directory : constant String := Ada.Directories.Full_Name ("obj/durability");
   Path      : constant String := Directory & "/written.txt";
   File      : Ada.Text_IO.File_Type;
   Written   : Hostkit.Durability.Outcome;
   Listed    : Hostkit.Durability.Outcome;
begin
   Ada.Directories.Create_Path (Directory);
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "kept");
   Ada.Text_IO.Close (File);
   Written := Hostkit.Durability.Sync_File (Path);
   Listed := Hostkit.Durability.Sync_Directory (Directory);
   AUnit.Assertions.Assert
     (Written = Hostkit.Durability.Synced,
      "a written file was not synced: " & Hostkit.Durability.Outcome'Image (Written));
   AUnit.Assertions.Assert
     (Listed /= Hostkit.Durability.Failed,
      "a directory's entries could not be synced: "
      & Hostkit.Durability.Outcome'Image (Listed));
   AUnit.Assertions.Assert
     (Hostkit.Durability.Sync_File (Directory & "/not-there.txt") = Hostkit.Durability.Failed,
      "a file that is not there was said to be synced");

   --  Room reserved is room the file has, its length grown to it; a
   --  file that is not there has none to reserve.
   declare
      use type Ada.Directories.File_Size;
      Reserved : constant Hostkit.Durability.Outcome :=
        Hostkit.Durability.Reserve_Space (Path, 1_048_576);
   begin
      if Hostkit.Host.Current = Hostkit.Host.Linux then
         AUnit.Assertions.Assert
           (Reserved = Hostkit.Durability.Synced,
            "room was not reserved: " & Hostkit.Durability.Outcome'Image (Reserved));
         AUnit.Assertions.Assert
           (Ada.Directories.Size (Path) = 1_048_576, "the file was not grown to the room reserved");
         AUnit.Assertions.Assert
           (Hostkit.Durability.Reserve_Space (Directory & "/not-there.txt", 4096)
              = Hostkit.Durability.Failed,
            "room was reserved for a file that is not there");
      else
         AUnit.Assertions.Assert
           (Reserved /= Hostkit.Durability.Synced,
            "room was said to be reserved where the host cannot");
      end if;
   end;
end Test_Writes_Are_Made_Durable;
