with Ada.Streams.Stream_IO;

with Hostkit.Desktop_Entries;

separate (Hostkit_Suite)
procedure Test_Desktop_Entry_Files (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   package Entries renames Hostkit.Desktop_Entries;
   use type Hostkit.Fs.Delete_Tree_Outcome;

   LF          : constant Character := ASCII.LF;
   CRLF        : constant String := ASCII.CR & ASCII.LF;
   Root        : constant String := Hostkit.Fs.Create_Temporary_Directory ("hk-desktop-entries");
   Apps        : constant String := Hostkit.Fs.Join (Hostkit.Fs.Join (Root, "user"), "applications");
   System_Apps : constant String := Hostkit.Fs.Join (Hostkit.Fs.Join (Root, "system"), "applications");
   Desktops    : constant String := "FilesTest:GNOME:Escaped;Desktop";

   --  The bytes exactly as given: no line ending added or translated.
   procedure Write (Path : String; Text : String) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      String'Write (Ada.Streams.Stream_IO.Stream (File), Text);
      Ada.Streams.Stream_IO.Close (File);
   end Write;

   --  Text, then Count spaces, written a piece at a time.
   procedure Write_Padded (Path : String; Text : String; Count : Natural) is
      File  : Ada.Streams.Stream_IO.File_Type;
      Piece : constant String (1 .. 4096) := [others => ' '];
      Left  : Natural := Count;
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      String'Write (Ada.Streams.Stream_IO.Stream (File), Text);
      while Left > 0 loop
         String'Write (Ada.Streams.Stream_IO.Stream (File), Piece (1 .. Natural'Min (Left, Piece'Length)));
         Left := Left - Natural'Min (Left, Piece'Length);
      end loop;
      Ada.Streams.Stream_IO.Close (File);
   end Write_Padded;

   type Name_List is array (Positive range <>) of Unbounded_String;
   function "+" (Text : String) return Unbounded_String renames To_Unbounded_String;

   function Entry_Text (Name, Exec : String; Extra : String := "") return String is
     ("[Desktop Entry]" & LF & "Type=Application" & LF & "Name=" & Name & LF & "Exec=" & Exec & LF & Extra);

   --  A path as a desktop-entry string: each backslash (a Windows
   --  separator) written as the \\ escape.
   function Escaped (Path : String) return String is
      Result : Unbounded_String;
   begin
      for C of Path loop
         Append (Result, (if C = '\' then "\\" else [C]));
      end loop;
      return To_String (Result);
   end Escaped;

   procedure Clean_Up is
   begin
      if Root /= "" and then Hostkit.Fs.Delete_Tree_No_Follow (Root) /= Hostkit.Fs.Tree_Deleted then
         null;
      end if;
   end Clean_Up;

   Folders : Hostkit.String_Vectors.Vector;
   Found   : Entries.Entry_Vectors.Vector;

   --  The entry listed under Name; Listed False when there is none.
   function Find (Name : String; Listed : out Boolean) return Entries.Desktop_Entry is
   begin
      for Item of Found loop
         if To_String (Item.Name) = Name then
            Listed := True;
            return Item;
         end if;
      end loop;
      Listed := False;
      return (others => <>);
   end Find;

   function Is_Listed (Name : String) return Boolean is
      Listed : Boolean;
      Ignore : constant Entries.Desktop_Entry := Find (Name, Listed);
      pragma Unreferenced (Ignore);
   begin
      return Listed;
   end Is_Listed;

   function Count_Named (Name : String) return Natural is
      Result : Natural := 0;
   begin
      for Item of Found loop
         if To_String (Item.Name) = Name then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Count_Named;

   Linked : Boolean;
begin
   Assert (Root /= "", "a temporary folder was made");
   Ada.Directories.Create_Path (Hostkit.Fs.Join (Hostkit.Fs.Join (Apps, "kde"), "sub"));
   Ada.Directories.Create_Path (System_Apps);

   --  What is listed.
   Write (Hostkit.Fs.Join (Apps, "editor.desktop"), Entry_Text ("Text Editor", "editor %F"));
   Write (Hostkit.Fs.Join (Apps, "crlf.desktop"),
          "[Desktop Entry]" & CRLF & "Type=Application" & CRLF & "Name=ZZ CRLF Application" & CRLF
          & "Exec=viewer %F" & CRLF);
   Write (Hostkit.Fs.Join (Apps, "viewer.desktop"),
          Entry_Text ("Image Viewer", "viewer --open %U",
                      "TryExec=" & Escaped (Hostkit.Fs.Own_Executable) & LF & "Terminal=false" & LF));
   Write (Hostkit.Fs.Join (Apps, "missing.desktop"),
          Entry_Text ("Z Missing", "/nonexistent-hostkit-test/program %F"));
   Write (Hostkit.Fs.Join (Apps, "same-one.desktop"), Entry_Text ("Shared Name", "viewer %F"));
   Write (Hostkit.Fs.Join (Apps, "same-two.desktop"), Entry_Text ("Shared Name", "viewer %F"));
   Write (Hostkit.Fs.Join (Apps, "only-current.desktop"),
          Entry_Text ("V Current Desktop", "viewer %F", "OnlyShowIn=FilesTest;" & LF));
   Write (Hostkit.Fs.Join (Apps, "not-other.desktop"),
          Entry_Text ("W Other Desktop Exclusion", "viewer %F", "NotShowIn=KDE;" & LF));
   Write (Hostkit.Fs.Join (Apps, "both-visibility.desktop"),
          Entry_Text ("X Both Visibility Lists", "viewer %F", "OnlyShowIn=FilesTest;" & LF & "NotShowIn=KDE;" & LF));
   Write (Hostkit.Fs.Join (Apps, "escaped-desktop.desktop"),
          Entry_Text ("Y Escaped Desktop Name", "viewer %F", "OnlyShowIn=Escaped\;Desktop;" & LF));
   Write (Hostkit.Fs.Join (Apps, "localized.desktop"),
          "[Desktop Entry]" & LF & "Type=Application" & LF
          & "Name=Fallback\sName" & LF & "Name[da]=Dansk\sNavn" & LF & "Name[da_DK]=Dansk\sProgram" & LF
          & "Icon=base\\icon" & LF & "Icon[da]=danish\\icon" & LF & "Icon[da_DK]=regional\\icon" & LF
          & "Exec=viewer --label=%c ""C:\\\\Temp"" %F %i" & LF);
   Write (Hostkit.Fs.Join (Apps, "plain.desktop"),
          "# a comment line" & LF
          & Entry_Text ("Plain", """/opt/My App/run"" --name=%c %U",
                        "Icon=plain-icon" & LF & "Comment=A\scomment" & LF & "Comment[da]=En\skommentar" & LF
                        & "Path=" & Escaped (Root) & LF & "Terminal=true" & LF
                        & "MimeType=text/plain;image/png;" & LF)
          & "[Desktop Action other]" & LF & "Exec=not-this-one" & LF);
   Write (Hostkit.Fs.Join (Apps, "bad-comment.desktop"),
          Entry_Text ("Bad Comment", "viewer", "Comment=bad\q" & LF & "MimeType=bad\q;" & LF));
   Write (Hostkit.Fs.Join (Hostkit.Fs.Join (Apps, "kde"), "konsole.desktop"), Entry_Text ("Konsole", "konsole"));
   Write (Hostkit.Fs.Join (Hostkit.Fs.Join (Hostkit.Fs.Join (Apps, "kde"), "sub"), "deep.desktop"),
          Entry_Text ("Deep", "deep"));
   Write (Hostkit.Fs.Join (Apps, "notes.txt"), Entry_Text ("Text File", "text"));

   --  What is not.
   Write (Hostkit.Fs.Join (Apps, "nodisplay.desktop"), Entry_Text ("Hidden Display", "nope", "NoDisplay=true" & LF));
   Write (Hostkit.Fs.Join (Apps, "hidden.desktop"), Entry_Text ("Gone", "nope", "Hidden=true" & LF));
   Write (Hostkit.Fs.Join (Apps, "link.desktop"),
          "[Desktop Entry]" & LF & "Type=Link" & LF & "Name=A Link" & LF & "Exec=nope" & LF);
   Write (Hostkit.Fs.Join (Apps, "noexec.desktop"), Entry_Text ("No Command", "%F"));
   Write (Hostkit.Fs.Join (Apps, "no-exec-key.desktop"),
          "[Desktop Entry]" & LF & "Type=Application" & LF & "Name=No Exec Key" & LF);
   Write (Hostkit.Fs.Join (Apps, "unknown-field.desktop"), Entry_Text ("Unknown Field", "viewer %Z"));
   Write (Hostkit.Fs.Join (Apps, "unterminated.desktop"), Entry_Text ("Unterminated", "viewer ""broken"));
   Write (Hostkit.Fs.Join (Apps, "invalid-boolean.desktop"),
          Entry_Text ("Invalid Boolean", "viewer %F", "Hidden=FALSE" & LF));
   Write (Hostkit.Fs.Join (Apps, "invalid-terminal.desktop"),
          Entry_Text ("Unclear Program", "viewer %F", "Terminal=maybe" & LF));
   Write (Hostkit.Fs.Join (Apps, "duplicate-key.desktop"),
          Entry_Text ("Duplicate Key", "viewer %F", "Hidden=true" & LF & "Hidden=false" & LF));
   Write (Hostkit.Fs.Join (Apps, "duplicate-group.desktop"),
          "[Desktop Entry]" & LF & "Type=Link" & LF & Entry_Text ("Duplicate Group", "viewer %F"));
   Write (Hostkit.Fs.Join (Apps, "duplicate-auxiliary-group.desktop"),
          Entry_Text ("Duplicate Auxiliary Group", "viewer %F",
                      "[Extra]" & LF & "Value=one" & LF & "[Extra]" & LF & "Value=two" & LF));
   Write (Hostkit.Fs.Join (Apps, "malformed-line.desktop"),
          Entry_Text ("Malformed Line", "viewer %F", "Hidden true" & LF));
   Write (Hostkit.Fs.Join (Apps, "malformed-group.desktop"),
          Entry_Text ("Malformed Group", "viewer %F", "[Broken" & LF));
   Write (Hostkit.Fs.Join (Apps, "invalid-escape.desktop"), Entry_Text ("Invalid Escape", "say \$HOME"));
   Write (Hostkit.Fs.Join (Apps, "localized-name-only.desktop"),
          "[Desktop Entry]" & LF & "Type=Application" & LF & "Name[da]=Localized Name Only" & LF
          & "Exec=viewer %F" & LF);
   Write (Hostkit.Fs.Join (Apps, "localized-icon-only.desktop"),
          Entry_Text ("Localized Icon Only", "viewer %F", "Icon[da]=localized-icon" & LF));
   Write (Hostkit.Fs.Join (Apps, "try-missing.desktop"),
          Entry_Text ("Try Missing", "viewer %F",
                      "TryExec=" & Escaped (Hostkit.Fs.Join (Root, "no-such-program")) & LF));
   Write (Hostkit.Fs.Join (Apps, "only-other.desktop"),
          Entry_Text ("Only Other Desktop", "viewer %F", "OnlyShowIn=KDE;" & LF));
   Write (Hostkit.Fs.Join (Apps, "not-current.desktop"),
          Entry_Text ("Not Current Desktop", "viewer %F", "NotShowIn=FilesTest;" & LF));
   Write (Hostkit.Fs.Join (Apps, "excluded-later.desktop"),
          Entry_Text ("Excluded By Later Desktop", "viewer %F",
                      "OnlyShowIn=FilesTest;" & LF & "NotShowIn=GNOME;" & LF));
   Write (Hostkit.Fs.Join (Apps, "invalid-list-escape.desktop"),
          Entry_Text ("Invalid List Escape", "viewer %F", "NotShowIn=FilesTest\q;" & LF));
   Write (Hostkit.Fs.Join (Apps, "overlapping-visibility.desktop"),
          Entry_Text ("Overlapping Visibility Lists", "viewer %F",
                      "OnlyShowIn=FilesTest;" & LF & "NotShowIn=FilesTest;" & LF));
   Write_Padded (Hostkit.Fs.Join (Apps, "oversized.desktop"), Entry_Text ("Oversized Entry", "viewer %F"), 1024 * 1024);
   Write (Hostkit.Fs.Join (Apps, "excessive-exec.desktop"),
          Entry_Text ("Excessive Exec", "viewer" & Ada.Strings.Fixed."*" (257, " a")));
   Write (Hostkit.Fs.Join (Apps, "long-line.desktop"),
          Entry_Text ("Long Line", "viewer", "X-Long=" & Ada.Strings.Fixed."*" (64 * 1024, 'x') & LF));

   --  An earlier folder's id masks a later one's, hidden or not, and a
   --  subfolder's id is its path joined with '-'.
   Write (Hostkit.Fs.Join (Apps, "masked.desktop"), Entry_Text ("Masked User Entry", "nope", "Hidden=true" & LF));
   Write (Hostkit.Fs.Join (System_Apps, "masked.desktop"), Entry_Text ("Should Stay Masked", "viewer %F"));
   Write (Hostkit.Fs.Join (System_Apps, "editor.desktop"), Entry_Text ("System Editor", "viewer %F"));
   Write (Hostkit.Fs.Join (System_Apps, "kde-konsole.desktop"), Entry_Text ("System Konsole", "konsole"));
   Write (Hostkit.Fs.Join (System_Apps, "system-only.desktop"), Entry_Text ("System Only", "viewer %F"));

   --  A linked entry is read; a linked folder is not walked into.
   Write (Hostkit.Fs.Join (Root, "linked-target.desktop"), Entry_Text ("Linked Application", "viewer %F"));
   Linked := Hostkit.Fs.Create_Link
     (Hostkit.Fs.Join (Root, "linked-target.desktop"), Hostkit.Fs.Join (Apps, "linked-application.desktop"));
   declare
      --  A loop that cannot be made only leaves less to walk.
      Loop_Made : constant Boolean := Hostkit.Fs.Create_Link (Apps, Hostkit.Fs.Join (Apps, "loop"));
      pragma Unreferenced (Loop_Made);
   begin
      null;
   end;
   if not Linked then
      Links_Refused ("Desktop_Entries.Scan, a linked entry");
   end if;

   --  A tree too deep to walk.
   declare
      Deep : Unbounded_String := To_Unbounded_String (Hostkit.Fs.Join (Apps, "deep"));
   begin
      for Level in 1 .. 66 loop
         Deep := +Hostkit.Fs.Join (To_String (Deep), [Character'Val (Character'Pos ('a') + Level mod 26)]);
      end loop;
      Ada.Directories.Create_Path (To_String (Deep));
      Write (Hostkit.Fs.Join (To_String (Deep), "too-deep.desktop"), Entry_Text ("Too Deep", "viewer %F"));
   end;

   Folders.Append (To_Unbounded_String (Apps));
   Folders.Append (To_Unbounded_String (System_Apps));
   Folders.Append (To_Unbounded_String (Hostkit.Fs.Join (Root, "no-such-folder")));
   Found := Entries.Scan (Folders, Entries.Locale_Candidates ("da_DK.UTF-8"), Desktops);

   Assert (Natural (Found.Length) = (if Linked then 17 else 16),
           "the listed entries, found" & Natural'Image (Natural (Found.Length)));
   for Name of Name_List'
     [+"Text Editor", +"ZZ CRLF Application",
       +"Image Viewer", +"Z Missing",
       +"V Current Desktop", +"W Other Desktop Exclusion",
       +"X Both Visibility Lists", +"Y Escaped Desktop Name",
       +"Dansk Program", +"Plain", +"Bad Comment",
       +"Konsole", +"Deep", +"System Only"]
   loop
      Assert (Is_Listed (To_String (Name)), To_String (Name) & " is listed");
   end loop;
   Assert (Count_Named ("Shared Name") = 2, "two ids may share a Name");
   Assert (Is_Listed ("Linked Application") = Linked, "a linked entry is listed, as Flatpak and NixOS install them");

   for Name of Name_List'
     [+"Text File", +"Hidden Display", +"Gone",
       +"A Link", +"No Command", +"No Exec Key",
       +"Unknown Field", +"Unterminated",
       +"Invalid Boolean", +"Unclear Program",
       +"Duplicate Key", +"Duplicate Group",
       +"Duplicate Auxiliary Group", +"Malformed Line",
       +"Malformed Group", +"Invalid Escape",
       +"Localized Name Only", +"Localized Icon Only",
       +"Try Missing", +"Only Other Desktop",
       +"Not Current Desktop", +"Excluded By Later Desktop",
       +"Invalid List Escape", +"Overlapping Visibility Lists",
       +"Oversized Entry", +"Excessive Exec",
       +"Long Line", +"Masked User Entry",
       +"Should Stay Masked", +"System Editor",
       +"System Konsole", +"Too Deep"]
   loop
      Assert (not Is_Listed (To_String (Name)), To_String (Name) & " is not listed");
   end loop;

   declare
      Listed : Boolean;
      Plain  : constant Entries.Desktop_Entry := Find ("Plain", Listed);
   begin
      Assert (To_String (Plain.Id) = "plain.desktop", "an entry at the top is under its file name");
      Assert (To_String (Plain.Location) = Hostkit.Fs.Join (Apps, "plain.desktop"), "its Location is its path");
      Assert (To_String (Plain.Exec) = """/opt/My App/run"" --name=%c %U", "Exec is kept for Command_For");
      Assert (To_String (Plain.Icon) = "plain-icon", "its Icon");
      Assert (To_String (Plain.Comment) = "En kommentar", "the localized Comment, its escape decoded");
      Assert (To_String (Plain.Working_Directory) = Root, "Path= is the working directory");
      Assert (Plain.Terminal, "Terminal=true is read");
      Assert (Natural (Plain.Mime_Types.Length) = 2
              and then To_String (Plain.Mime_Types.Last_Element) = "image/png", "MimeType is a list");
   end;

   declare
      Bad_Listed, Konsole_Listed, Deep_Listed, Viewer_Listed, Danish_Listed : Boolean;
      Bad     : constant Entries.Desktop_Entry := Find ("Bad Comment", Bad_Listed);
      Konsole : constant Entries.Desktop_Entry := Find ("Konsole", Konsole_Listed);
      Deep    : constant Entries.Desktop_Entry := Find ("Deep", Deep_Listed);
      Viewer  : constant Entries.Desktop_Entry := Find ("Image Viewer", Viewer_Listed);
      Danish  : constant Entries.Desktop_Entry := Find ("Dansk Program", Danish_Listed);
   begin
      Assert (Bad_Listed and then Konsole_Listed and then Deep_Listed and then Viewer_Listed and then Danish_Listed,
              "every entry the checks below read is listed");
      Assert (To_String (Bad.Comment) = "" and then Bad.Mime_Types.Is_Empty,
              "a Comment or MimeType that does not decode is dropped, not the entry");
      Assert (To_String (Konsole.Id) = "kde-konsole.desktop", "a subfolder's entry is under a '-'-joined id");
      Assert (To_String (Deep.Id) = "kde-sub-deep.desktop", "each folder level joins the id with '-'");
      Assert (not Viewer.Terminal and then To_String (Viewer.Working_Directory) = "",
              "Terminal=false is a window program with no working directory");
      Assert (To_String (Viewer.Exec) = "viewer --open %U", "Exec keeps its field codes");
      Assert (To_String (Danish.Icon) = "regional\icon", "the best localized Icon, decoded");
      Assert (To_String (Danish.Exec) = "viewer --label=%c ""C:\\Temp"" %F %i",
              "Exec's string escapes are decoded, its own quoting kept");
   end;

   --  One file read alone, with no locales and another desktop.
   declare
      Item  : Entries.Desktop_Entry;
      Is_In : Boolean;
   begin
      Entries.Parse (Hostkit.Fs.Join (Apps, "localized.desktop"), Item, Is_In, Id => "localized.desktop");
      Assert (Is_In and then To_String (Item.Name) = "Fallback Name" and then To_String (Item.Icon) = "base\icon",
              "with no locales the unlocalized values are read");
      Entries.Parse (Hostkit.Fs.Join (Apps, "only-current.desktop"), Item, Is_In, Current_Desktop => "KDE");
      Assert (not Is_In, "an entry only for another desktop is not listed there");
      Entries.Parse (Hostkit.Fs.Join (Root, "no-such.desktop"), Item, Is_In);
      Assert (not Is_In, "a file that is not there is no entry");
      Entries.Parse (Apps, Item, Is_In);
      Assert (not Is_In, "a folder is no entry");
   end;

   --  The host's own folders.
   for Folder of Entries.Application_Folders loop
      Assert (Ada.Directories.Simple_Name (To_String (Folder)) = "applications",
              "each folder is an applications folder: " & To_String (Folder));
   end loop;
   Assert (Entries.Application_Folders.Is_Empty = (Hostkit.Host.Current /= Hostkit.Host.Linux),
           "Linux has applications folders; Windows and macOS keep no desktop entries");

   Clean_Up;
exception
   when others =>
      Clean_Up;
      raise;
end Test_Desktop_Entry_Files;
