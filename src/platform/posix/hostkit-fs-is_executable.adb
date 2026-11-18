separate (Hostkit.Fs)
function Is_Executable (Path : String) return Boolean is
   use type Ada.Directories.File_Kind;
begin
   --  Kind alone, not Exists and then Kind: Kind raises Name_Error for a path
   --  that is not there, which the handler below already turns into False.
   --  The Exists call was a third stat of the same path for an answer the
   --  next one gives, and a directory listing pays this per file.
   return Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File
     and then GNAT.OS_Lib.Is_Executable_File (Path);
exception
   when others =>
      return False;
end Is_Executable;
