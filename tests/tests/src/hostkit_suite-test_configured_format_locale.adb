separate (Hostkit_Suite)
--  The desktop's configured formats: on Linux read from KDE Plasma's
--  plasma-localerc under the given home ([Formats], the category's key before
--  LANG; shell-style quotes taken off, unmatched ones kept, an oversized file
--  ignored); on Windows and macOS part of the regional setting, so "".
procedure Test_Configured_Format_Locale
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use Hostkit.Host;
   LF     : constant Character := ASCII.LF;
   Home   : constant String := Scratch & "/hostkit-locale-home";
   Config : constant String := Home & "/.config";
   File   : constant String := Config & "/plasma-localerc";

   procedure Expect (Category : Format_Category; Wanted, What : String) is
      Got : constant String := Configured_Format_Locale (Category, Home);
   begin
      --  /etc may configure LANG on the machine running this: only an answer
      --  from the fixture is checked exactly.
      Assert (Got = Wanted, What & ": got """ & Got & """, wanted """ & Wanted & """");
   end Expect;
begin
   if Ada.Directories.Exists (Home) then
      Ada.Directories.Delete_Tree (Home);
   end if;
   Ada.Directories.Create_Path (Config);
   if Current /= Linux then
      Write_File (File, "[Formats]" & LF & "LANG=de_DE.UTF-8" & LF);
      Assert (Configured_Format_Locale (Time_Formats, Home) = "", "this host keeps its formats in its settings");
      Ada.Directories.Delete_Tree (Home);
      return;
   end if;

   Write_File
     (File,
      "LANG=xx_XX.UTF-8" & LF
      & "[Other]" & LF & "LC_TIME=yy_YY.UTF-8" & LF
      & "[Formats]" & ASCII.CR & LF
      & "LC_NUMERIC='da_DK.UTF-8'" & ASCII.CR & LF
      & "LANG=""de_DE.UTF-8""" & LF);
   Expect (Time_Formats, "de_DE.UTF-8", "LANG in [Formats], double quotes taken off");
   Expect (Number_Formats, "da_DK.UTF-8", "the category's own key first, single quotes taken off");

   Write_File (File, "[Formats]" & LF & "LC_TIME=""sv_SE.UTF-8'" & LF & "LC_NUMERIC=""" & LF);
   Expect (Time_Formats, """sv_SE.UTF-8'", "quotes that do not match are kept");
   Expect (Number_Formats, """", "a lone quote is no pair");

   declare
      Big : constant String (1 .. 256 * 1024) := [others => '#'];
   begin
      Write_File (File, "[Formats]" & LF & "LC_TIME=fr_FR.UTF-8" & LF & Big);
      Assert (Configured_Format_Locale (Time_Formats, Home) /= "fr_FR.UTF-8", "an oversized file is not read");
   end;
   Ada.Directories.Delete_Tree (Home);
end Test_Configured_Format_Locale;
