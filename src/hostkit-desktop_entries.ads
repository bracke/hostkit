with Ada.Containers.Vectors;

--  Desktop Entry files: the freedesktop Desktop Entry Specification's
--  .desktop files, by which a POSIX desktop lists the applications it can
--  start -- found under the "applications" folder of each of
--  Fs.Application_Data_Directories (XDG_DATA_HOME, then XDG_DATA_DIRS), in
--  that order of precedence.
--
--  The reading is the same on every host; it is here because each program
--  that starts what the desktop lists (a file manager's Open With, an
--  application launcher) has to read these files exactly as the desktop
--  does, and two copies of the reading had already come to disagree: one
--  passed an Exec line with an unknown escape on to the program, the other
--  refused the entry, so one program offered what another hid.
--
--  An entry is read strictly. Its [Desktop Entry] group's keys must be
--  well-formed (a malformed line or group header, a duplicate key or group,
--  an invalid boolean or string escape, a localized value without its base
--  key: the file is no entry), string escapes are decoded (\s \n \t \r \\,
--  and \; inside a list), Name, Icon and Comment take the best localized
--  value for the given locales, and Exec is split by its own quoting rules
--  into an argument vector with its field codes (%f %F %u %U %i %c %k %%)
--  expanded. An entry is listed only when it is an Application, neither
--  Hidden nor NoDisplay, its TryExec program (if any) is runnable here, the
--  current desktops are allowed by OnlyShowIn and NotShowIn, and its Exec
--  splits and expands into a program. Files are bounded (1 MiB, 64 KiB a
--  line, 4096 keys and groups, 256 list items and Exec arguments) before they are
--  read, so a hostile entry costs nothing.
package Hostkit.Desktop_Entries is

   --  One listed entry.
   type Desktop_Entry is record
      --  The desktop-file id: the path below its "applications" folder, each
      --  folder separator turned into '-' ("kde/konsole.desktop" is
      --  "kde-konsole.desktop").
      Id                : UString;
      --  The .desktop file's path, as %k expands to.
      Location          : UString;
      --  Name, the best localized value for the locales asked for.
      Name              : UString;
      --  Exec, string escapes decoded but its own quoting and field codes
      --  kept: what Command_For takes.
      Exec              : UString;
      --  Icon (an icon name or a path), localized as Name; "" when none.
      Icon              : UString;
      --  Comment, localized as Name; "" when none or not decodable (a bad
      --  comment does not hide an application).
      Comment           : UString;
      --  Terminal=true: the program runs inside a terminal emulator, which
      --  the caller supplies (Process.Default_Terminal and
      --  Process.Terminal_Program_Prefix).
      Terminal          : Boolean := False;
      --  Path=: the folder the entry asks to be started in, or "".
      Working_Directory : UString;
      --  MimeType: the types the application opens; empty when none or not
      --  decodable.
      Mime_Types        : String_Vectors.Vector;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Desktop_Entry);

   --  The locale postfixes a localized key ("Name[da_DK]") is matched
   --  against, best first, for a POSIX locale name: lang_COUNTRY@MODIFIER,
   --  lang_COUNTRY, lang@MODIFIER, lang -- each that the name has, once. The
   --  encoding (".UTF-8") is ignored, and blanks around the name.
   --
   --  @param Locale A locale name ("da_DK.UTF-8"), or "".
   --  @return The postfixes; empty for "".
   function Locale_Candidates (Locale : String) return String_Vectors.Vector;

   --  Locale_Candidates for the locale messages are shown in: the first of
   --  LC_ALL, LC_MESSAGES and LANG that is set to something.
   --
   --  @return The postfixes; empty when none of them is set.
   function Message_Locale_Candidates return String_Vectors.Vector;

   --  The current desktops: XDG_CURRENT_DESKTOP, a ':'-separated list of
   --  desktop names ("ubuntu:GNOME"), or "" when it is not set.
   --
   --  @return The variable's value.
   function Current_Desktops return String;

   --  Decode a string, localestring or iconstring value's escapes: \s, \n,
   --  \t, \r and \\ become a space, a newline, a tab, a carriage return and
   --  a backslash. Any other backslash -- one at the end included -- makes
   --  the value invalid, and the entry holding it is no entry.
   --
   --  @param Value A raw value, as it follows '=' in the file.
   --  @param Decoded The decoded value; "" when invalid.
   --  @return False when the value holds an invalid escape.
   function Decode_Value (Value : String; Decoded : out UString) return Boolean;

   --  Decode a string(s) value: items separated by ';' (a trailing ';' is
   --  customary), each decoded as Decode_Value does, with \; an escaped ';'
   --  inside an item.
   --
   --  @param Value A raw value.
   --  @param Items The items; empty when invalid.
   --  @return False for an invalid escape or more than 256 items.
   function Decode_List (Value : String; Items : out String_Vectors.Vector) return Boolean;

   --  Whether an entry is meant for the current desktops: when OnlyShowIn is
   --  given, one of the current desktops must be in it; none of them may be
   --  in NotShowIn, and one name may not be in both. Names compare with
   --  case.
   --
   --  @param Only_Show_In The raw OnlyShowIn value, or "" when there is none.
   --  @param Not_Show_In The raw NotShowIn value, or "" when there is none.
   --  @param Current_Desktop The current desktops, ':'-separated (Current_Desktops).
   --  @return True when the entry should be shown; False too when a list
   --    cannot be decoded.
   function Shown_In
     (Only_Show_In    : String;
      Not_Show_In     : String;
      Current_Desktop : String)
      return Boolean;

   --  Split a (string-decoded) Exec value into its arguments, the program
   --  first: separated by spaces or tabs, a double-quoted argument may hold
   --  them, and a backslash makes the character after it literal (inside
   --  quotes and out). Quotes and those backslashes are removed; field codes
   --  are kept, for Expand_Field_Codes. A field code inside quotes is
   --  refused (only %% is allowed there), as the specification has it.
   --
   --  @param Exec The Exec value, as Desktop_Entry.Exec holds it.
   --  @param Arguments The arguments; empty when refused.
   --  @return False for an unbalanced quote, a trailing backslash, a field
   --    code inside quotes, a value over 64 KiB or more than 256 arguments.
   function Split_Exec (Exec : String; Arguments : out String_Vectors.Vector) return Boolean;

   --  Expand the field codes in Split_Exec's arguments, for a launch on
   --  Targets. The program may hold %% (a literal '%') and no other field
   --  code, and no '=' (an environment assignment is not a program). In
   --  the arguments: %F and %U, which must be a whole argument, become
   --  every target, each its own argument; %f and %u the first target (an
   --  argument that held only a field code and expands to nothing goes); %i,
   --  which must be a whole argument, becomes the two arguments --icon and
   --  Icon (none when Icon is ""); %c becomes Name, %k Location, %% a '%';
   --  the deprecated %d %D %n %N %v %m nothing. Only one target code may
   --  appear. Targets are not added when there is no target code: that is
   --  the caller's to decide (Target_Field says).
   --
   --  @param Arguments Split_Exec's arguments, the program first.
   --  @param Name The entry's Name.
   --  @param Icon The entry's Icon, or "".
   --  @param Location The .desktop file's path.
   --  @param Targets The files or URLs to open; empty for none.
   --  @param Command The program, then its arguments; empty when refused.
   --  @param Target_Field True when the command has a target code.
   --  @return False for an unknown field code, a misplaced %F %U or %i, a
   --    second target code, or no usable program.
   function Expand_Field_Codes
     (Arguments    : String_Vectors.Vector;
      Name         : String;
      Icon         : String;
      Location     : String;
      Targets      : String_Vectors.Vector;
      Command      : out String_Vectors.Vector;
      Target_Field : out Boolean)
      return Boolean;

   --  Split_Exec and then Expand_Field_Codes.
   --
   --  @param Exec The Exec value, as Desktop_Entry.Exec holds it.
   --  @param Name The entry's Name.
   --  @param Icon The entry's Icon, or "".
   --  @param Location The .desktop file's path.
   --  @param Targets The files or URLs to open; empty for none.
   --  @param Command The program, then its arguments; empty when refused.
   --  @param Target_Field True when the command has a target code.
   --  @return False when Exec cannot be split or expanded.
   function Command_For
     (Exec         : String;
      Name         : String;
      Icon         : String;
      Location     : String;
      Targets      : String_Vectors.Vector;
      Command      : out String_Vectors.Vector;
      Target_Field : out Boolean)
      return Boolean;

   --  Whether Exec opens one target a launch (%f or %u), so that several
   --  targets take a launch each, where %F and %U take them all at once.
   --
   --  @param Exec The Exec value, as Desktop_Entry.Exec holds it.
   --  @return True when an argument holds %f or %u.
   function Takes_One_Target (Exec : String) return Boolean;

   --  Read one .desktop file.
   --
   --  @param Path The .desktop file; a link to one is followed.
   --  @param Item The entry, valid only when Found.
   --  @param Found True when the file is an entry to list here (see the
   --    package's description).
   --  @param Id Its desktop-file id, for Item.Id.
   --  @param Locales The locale postfixes for localized values, best first
   --    (Locale_Candidates); empty for the unlocalized values.
   --  @param Current_Desktop The current desktops, for OnlyShowIn and NotShowIn.
   procedure Parse
     (Path            : String;
      Item            : out Desktop_Entry;
      Found           : out Boolean;
      Id              : String := "";
      Locales         : String_Vectors.Vector := String_Vectors.Empty_Vector;
      Current_Desktop : String := Current_Desktops);

   --  The "applications" folder of each of Fs.Application_Data_Directories,
   --  highest precedence first; empty on a host without such entries.
   --
   --  @return The folders, existing or not.
   function Application_Folders return String_Vectors.Vector;

   --  Read every entry under Folders and their subfolders, de-duplicated by
   --  desktop-file id: the first file met under an id decides, listed or
   --  not, so an earlier folder's Hidden entry masks a later one's. A linked
   --  .desktop file is read (Flatpak exports and NixOS entries are links); a
   --  linked folder is not descended into, and the walk stops 64 folders
   --  deep and after 100 000 entries. A folder that cannot be read holds
   --  nothing.
   --
   --  @param Folders "applications" folders, highest precedence first
   --    (Application_Folders).
   --  @param Locales The locale postfixes for localized values, best first.
   --  @param Current_Desktop The current desktops, for OnlyShowIn and NotShowIn.
   --  @return The entries to list, in the order they were found.
   function Scan
     (Folders         : String_Vectors.Vector;
      Locales         : String_Vectors.Vector := String_Vectors.Empty_Vector;
      Current_Desktop : String := Current_Desktops)
      return Entry_Vectors.Vector;

end Hostkit.Desktop_Entries;
