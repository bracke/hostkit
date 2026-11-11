separate (Hostkit_Suite)
procedure Test_Font_Directories_Are_The_Hosts
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Entry_Kind;
   Folders : constant Hostkit.Fs.Path_List := Hostkit.Fs.Font_Directories;
   Home    : constant String := Hostkit.Fs.Home_Directory;

   function Lower (Text : String) return String renames Ada.Characters.Handling.To_Lower;

   function Times_Listed (Folder : String) return Natural is
      Count : Natural := 0;
   begin
      for Item of Folders loop
         if To_String (Item) = Folder then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Times_Listed;

   function Listed (Folder : String) return Boolean is (Times_Listed (Folder) > 0);
begin
   Assert (Folders'Length > 0, "every host this crate runs on keeps fonts somewhere");
   for Item of Folders loop
      Assert
        (Hostkit.Path_Text.Root_Length (To_String (Item)) > 0,
         "a font folder is absolute: " & To_String (Item));
      Assert (Times_Listed (To_String (Item)) = 1, "and listed once: " & To_String (Item));
   end loop;
   case Hostkit.Host.Current is
      when Hostkit.Host.Windows =>
         declare
            First : constant String := Lower (To_String (Folders (Folders'First)));
         begin
            Assert
              (First'Length > 6 and then First (First'Last - 5 .. First'Last) = "\fonts",
               "the system's Fonts folder comes first: " & First);
            Assert
              (Hostkit.Fs.Kind_Of (First) = Hostkit.Fs.Directory_Entry,
               "and is there: " & First);
            Assert
              (Folders'Length = 2
               and then Ada.Strings.Fixed.Index
                 (Lower (To_String (Folders (Folders'Last))), "\microsoft\windows\fonts") > 0,
               "then the folder a font installed for this user alone goes to");
         end;
      when Hostkit.Host.MacOS =>
         Assert
           (Listed ("/System/Library/Fonts") and then Listed ("/Library/Fonts"),
            "the system's and the machine's font folders");
         Assert (Home = "" or else Listed (Home & "/Library/Fonts"), "and the user's own");
      when others =>
         Assert (To_String (Folders (Folders'First)) = "/usr/share/fonts", "fontconfig's system folder comes first");
         Assert (Home = "" or else Listed (Home & "/.fonts"), "and the user's own folders follow");
   end case;
end Test_Font_Directories_Are_The_Hosts;
