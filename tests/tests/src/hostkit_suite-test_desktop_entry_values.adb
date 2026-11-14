with Hostkit.Desktop_Entries;

separate (Hostkit_Suite)
procedure Test_Desktop_Entry_Values (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   package Entries renames Hostkit.Desktop_Entries;
   subtype Vector is Hostkit.String_Vectors.Vector;

   function Image (Items : Vector) return String is
      Result : Unbounded_String;
   begin
      for Item of Items loop
         Append (Result, "[" & Item & "]");
      end loop;
      return To_String (Result);
   end Image;

   function Decoded (Value : String) return String is
      Text : Unbounded_String;
   begin
      if not Entries.Decode_Value (Value, Text) then
         return "<invalid>";
      end if;
      return To_String (Text);
   end Decoded;

   function List (Value : String) return String is
      Items : Vector;
   begin
      if not Entries.Decode_List (Value, Items) then
         return "<invalid>";
      end if;
      return Image (Items);
   end List;

   function Split (Exec : String) return String is
      Items : Vector;
   begin
      if not Entries.Split_Exec (Exec, Items) then
         return "<refused>";
      end if;
      return Image (Items);
   end Split;

   function Targets (A : String := ""; B : String := "") return Vector is
      Result : Vector;
   begin
      if A /= "" then
         Result.Append (To_Unbounded_String (A));
      end if;
      if B /= "" then
         Result.Append (To_Unbounded_String (B));
      end if;
      return Result;
   end Targets;

   --  The command an Exec value makes, "+" after it when it has a target code.
   function Command
     (Exec     : String;
      Files    : Vector := Hostkit.String_Vectors.Empty_Vector;
      Icon     : String := "";
      Name     : String := "My App";
      Location : String := "/usr/share/applications/my.desktop")
      return String
   is
      Items        : Vector;
      Target_Field : Boolean;
   begin
      if not Entries.Command_For (Exec, Name, Icon, Location, Files, Items, Target_Field) then
         return "<refused>";
      end if;
      return Image (Items) & (if Target_Field then "+" else "");
   end Command;
begin
   --  String escapes: the five the specification has, and nothing else.
   Assert (Decoded ("plain") = "plain", "a value with no escapes is unchanged");
   Assert (Decoded ("a\sb") = "a b", "\s is a space");
   Assert (Decoded ("a\nb\tc\rd") = "a" & ASCII.LF & "b" & ASCII.HT & "c" & ASCII.CR & "d",
           "\n \t \r are newline, tab and carriage return");
   Assert (Decoded ("C:\\Tools") = "C:\Tools", "\\ is one backslash");
   Assert (Decoded ("say \$HOME") = "<invalid>", "another escape makes the value invalid");
   Assert (Decoded ("ends\") = "<invalid>", "so does a trailing backslash");

   --  Lists.
   Assert (List ("GNOME;KDE;") = "[GNOME][KDE]", "a trailing ';' ends the last item");
   Assert (List ("GNOME;KDE") = "[GNOME][KDE]", "and is not needed");
   Assert (List ("Escaped\;Desktop;") = "[Escaped;Desktop]", "\; is a ';' inside an item");
   Assert (List ("a\sb;") = "[a b]", "items decode the string escapes");
   Assert (List ("bad\q;") = "<invalid>", "an unknown escape makes the list invalid");
   Assert (List ("") = "", "nothing is no items");

   --  Locales, best first.
   Assert (Image (Entries.Locale_Candidates ("da_DK.UTF-8")) = "[da_DK][da]", "the encoding is ignored");
   Assert (Image (Entries.Locale_Candidates ("sr_RS@latin")) = "[sr_RS@latin][sr_RS][sr@latin][sr]",
           "country and modifier are each dropped in turn");
   Assert (Image (Entries.Locale_Candidates ("de")) = "[de]", "a bare language is itself");
   Assert (Image (Entries.Locale_Candidates ("")) = "", "no locale, no candidates");

   --  Exec splitting.
   Assert (Split ("firefox") = "[firefox]", "a bare program");
   Assert (Split ("env  X=1   /usr/bin/foo") = "[env][X=1][/usr/bin/foo]", "runs of spaces separate arguments");
   Assert (Split ("""/opt/My App/run"" --flag") = "[/opt/My App/run][--flag]", "a quoted argument keeps its spaces");
   Assert (Split ("sh -c ""echo \""hi\"" \$HOME \`x\` \\""") = "[sh][-c][echo ""hi"" $HOME `x` \]",
           "a backslash makes the next character literal");
   Assert (Split ("app """"") = "[app][]", "an empty quoted argument is an argument");
   Assert (Split ("pre""fix""ed") = "[prefixed]", "quotes join with the text around them");
   Assert (Split ("app ""open") = "<refused>", "an open quote is refused");
   Assert (Split ("app end\") = "<refused>", "a trailing backslash is refused");
   Assert (Split ("printf ""%f""") = "<refused>", "a field code inside quotes is refused");
   Assert (Split ("printf ""100%% done""") = "[printf][100%% done]", "an escaped %% inside quotes is kept");
   Assert (Split ("") = "", "nothing is no arguments");
   declare
      Long : Unbounded_String := To_Unbounded_String ("viewer" & Ada.Strings.Fixed."*" (255, " a"));
   begin
      Assert (Split (To_String (Long)) /= "<refused>", "256 arguments are accepted");
      Append (Long, " a");
      Assert (Split (To_String (Long)) = "<refused>", "257 are refused");
   end;

   --  Field codes, with no target.
   Assert (Command ("gimp %f") = "[gimp]+", "a lone %f disappears, leaving no empty argument");
   Assert (Command ("vlc --started-from-file %U") = "[vlc][--started-from-file]+", "a lone %U disappears");
   Assert (Command ("app %d %D %n %N %v %m") = "[app]", "the deprecated codes all go");
   Assert (Command ("app %F %u") = "<refused>", "a second target code is refused");
   Assert (Command ("app %i", Icon => "app-icon") = "[app][--icon][app-icon]", "%i is --icon and the Icon");
   Assert (Command ("app %i") = "[app]", "%i with no Icon is nothing");
   Assert (Command ("app x%iy", Icon => "app-icon") = "<refused>", "%i inside an argument is refused");
   Assert (Command ("app x%Fy") = "<refused>", "so is %F");
   Assert (Command ("app --title=%c") = "[app][--title=My App]", "%c is the Name, inside an argument too");
   Assert (Command ("app %c") = "[app][My App]", "%c is one argument even with a space in it");
   Assert (Command ("app %k") = "[app][/usr/share/applications/my.desktop]", "%k is the file's path");
   Assert (Command ("show 100%%") = "[show][100%]", "%% is a single %");
   Assert (Command ("app %%d %f") = "[app][%d]+", "a %% is kept while %f is dropped");
   Assert (Command ("viewer %Z") = "<refused>", "an unknown field code is refused");
   Assert (Command ("app 100%") = "<refused>", "a lone % at the end is refused");
   Assert (Command ("viewer%%tool %F") = "[viewer%tool]+", "a %% in the program is a %");
   Assert (Command ("%F") = "<refused>", "a field code is no program");
   Assert (Command ("X=1 app") = "<refused>", "an environment assignment is no program");
   Assert (Command ("""""") = "<refused>", "an empty program is none");
   Assert (Command ("") = "<refused>", "nor is nothing");

   --  Field codes, with targets.
   Assert (Command ("viewer --open %U", Targets ("/tmp/a.txt", "/tmp/b.txt"))
           = "[viewer][--open][/tmp/a.txt][/tmp/b.txt]+", "%U is every target, each its own argument");
   Assert (Command ("viewer --before %f --after", Targets ("/tmp/a.txt", "/tmp/b.txt"))
           = "[viewer][--before][/tmp/a.txt][--after]+", "%f is the first target, in its place");
   Assert (Command ("viewer --file=%u", Targets ("/tmp/a.txt")) = "[viewer][--file=/tmp/a.txt]+",
           "%u inside an argument");
   Assert (Command ("viewer --open", Targets ("/tmp/a.txt")) = "[viewer][--open]",
           "with no target code the targets are the caller's to add");
   Assert (Command ("printf ""100%% done"" %f", Targets ("/tmp/a.txt")) = "[printf][100% done][/tmp/a.txt]+",
           "a quoted %% becomes one percent sign and the code after it still expands");
   Assert (Command ("""/opt/Quoted Editor/bin/editor"" ""--mode=two words"" %F --after %% %c %i %k",
                    Targets ("/tmp/a file.txt", "/tmp/b.txt"),
                    Icon => "quoted-icon", Name => "Quoted App", Location => "/apps/quoted.desktop")
           = "[/opt/Quoted Editor/bin/editor][--mode=two words][/tmp/a file.txt][/tmp/b.txt][--after][%]"
             & "[Quoted App][--icon][quoted-icon][/apps/quoted.desktop]+",
           "quoted arguments and field codes expand in place, argument boundaries intact");
   Assert (Command ("viewer --label=%c ""C:\\Temp"" %F %i", Targets ("/tmp/a.txt"),
                    Icon => "regional\icon", Name => "Dansk Program")
           = "[viewer][--label=Dansk Program][C:\Temp][/tmp/a.txt][--icon][regional\icon]+",
           "an Exec quoting escape keeps a Windows separator");

   --  One launch per target, or one for all.
   Assert (Entries.Takes_One_Target ("viewer --before %f --after"), "%f takes one target a launch");
   Assert (Entries.Takes_One_Target ("viewer --file=%u"), "so does %u inside an argument");
   Assert (not Entries.Takes_One_Target ("viewer %F"), "%F takes them all");
   Assert (not Entries.Takes_One_Target ("viewer 100%%f"), "an escaped percent is no field code");
   Assert (not Entries.Takes_One_Target ("viewer ""broken"), "an Exec that does not split takes none");

   --  OnlyShowIn and NotShowIn against the current desktops.
   Assert (Entries.Shown_In ("", "", ""), "no restriction shows everywhere");
   Assert (Entries.Shown_In ("", "", "KDE"), "no restriction shows on any desktop");
   Assert (Entries.Shown_In ("GNOME;KDE;", "", "KDE"), "OnlyShowIn naming the desktop shows it");
   Assert (not Entries.Shown_In ("GNOME;", "", "KDE"), "OnlyShowIn naming another desktop hides it");
   Assert (not Entries.Shown_In ("GNOME;", "", ""), "OnlyShowIn with no current desktop hides it");
   Assert (Entries.Shown_In ("GNOME;", "", "ubuntu:GNOME"), "any of the current desktops may match");
   Assert (not Entries.Shown_In ("", "KDE;", "KDE"), "NotShowIn naming the desktop hides it");
   Assert (Entries.Shown_In ("", "KDE;", "GNOME"), "NotShowIn naming another desktop shows it");
   Assert (not Entries.Shown_In ("", "XFCE;", "ubuntu:XFCE"), "any current desktop in NotShowIn hides it");
   Assert (not Entries.Shown_In ("GNOME;", "", "gnome"), "desktop names compare with case");
   Assert (not Entries.Shown_In ("FilesTest;", "GNOME;", "FilesTest:GNOME"),
           "a later exclusion wins over an earlier match");
   Assert (not Entries.Shown_In ("KDE;", "KDE;", "GNOME"), "one name may not be in both lists");
   Assert (Entries.Shown_In ("Escaped\;Desktop;", "", "Escaped;Desktop"), "the lists' escapes are decoded");
   Assert (not Entries.Shown_In ("", "KDE\q;", "GNOME"), "a list that does not decode hides the entry");
end Test_Desktop_Entry_Values;
