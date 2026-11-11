--  Handing a path to a wide Windows file API, and reading a name back.
--
--  Without a prefix, CreateFileW, CreateDirectoryW and the rest refuse a path
--  longer than MAX_PATH (260 UTF-16 units; 248 for a directory to be created)
--  unless the process opted into long paths through its manifest and the
--  registry. The \\?\ form (\\?\UNC\ for a share) lifts that limit, at the cost
--  of the normalisation the API otherwise does: no '/' to '\' translation and no
--  "." or ".." resolution. So only an absolute path that needs the prefix gets
--  it, and only once it is in a form the prefix leaves meaning the same. The
--  rules are pure text, so they live in the shared source and are tested on
--  every platform.
--
--  A Windows name is UTF-16 that need not be well formed: NTFS keeps a lone
--  surrogate in a name as readily as any other unit, and such a name cannot
--  be UTF-8. To_UTF_8 and From_UTF_8 carry it anyway, as WTF-8 -- the lone
--  surrogate as the three bytes its code point would take (ED A0..BF xx) --
--  so the name lists, and goes back to the API as the same units. Text that
--  is UTF-8 converts exactly as it would by Ada.Strings.UTF_Encoding, save
--  that a leading U+FEFF is a character of the name, not a byte order mark.
package Hostkit.Windows_Paths is

   Long_Path_Threshold : constant := 248;
   --  From this length on a path is given the \\?\ form.

   function Long_Path_Form (Path : String) return String;
   --  Path itself when it is shorter than Long_Path_Threshold, already
   --  prefixed (\\?\ or \\.\), relative, or carries a "." or ".." component;
   --  otherwise, with '/' read as '\', a drive path X:\... as \\?\X:\... and a
   --  share \\server\share\... as \\?\UNC\server\share\....

   function Native_Form (Path : String; Base : String) return String;
   --  Long_Path_Form of Path, except that a path of at least
   --  Long_Path_Threshold characters that is relative or carries a "." or ".."
   --  component is first made absolute against Base and its dot components
   --  resolved (Path_Text.Absolute), as GetFullPathNameW would, so it can
   --  take the prefix too: Windows resolves ".." in the text, not through a
   --  link, so the two read the same. A short path is left as it is.

   function Native (Path : String) return Wide_String;
   --  Native_Form (Path, Fs.Current_Directory) as UTF-16 (From_UTF_8) with a
   --  terminating NUL, ready to pass by address to a wide file API.

   function To_UTF_8 (Units : Wide_String) return String;
   --  Units, UTF-16 as a Windows API hands it back, as WTF-8: UTF-8 for each
   --  character, a well-formed surrogate pair as the four bytes of the one
   --  character it encodes, and a lone surrogate as the three bytes of its own
   --  code point. Never raises.

   function From_UTF_8 (Text : String) return Wide_String;
   --  Text as UTF-16: the inverse of To_UTF_8, so a lone surrogate's three
   --  bytes come back as that unit (and two encoded halves of a pair as the
   --  pair). Raises Ada.Strings.UTF_Encoding.Encoding_Error on bytes that are
   --  neither UTF-8 nor an encoded surrogate: a stray continuation byte, a
   --  truncated or overlong sequence, or a code point past U+10FFFF.

end Hostkit.Windows_Paths;
