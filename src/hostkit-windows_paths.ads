--  Handing a path to a wide Windows file API.
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
package Hostkit.Windows_Paths is

   Long_Path_Threshold : constant := 248;
   --  From this length on a path is given the \\?\ form.

   function Long_Path_Form (Path : String) return String;
   --  Path itself when it is shorter than Long_Path_Threshold, already
   --  prefixed (\\?\ or \\.\), relative, or carries a "." or ".." component;
   --  otherwise, with '/' read as '\', a drive path X:\... as \\?\X:\... and a
   --  share \\server\share\... as \\?\UNC\server\share\....

   function Native (Path : String) return Wide_String;
   --  Long_Path_Form (Path) as UTF-16 with a terminating NUL, ready to pass
   --  by address to a wide file API.

end Hostkit.Windows_Paths;
