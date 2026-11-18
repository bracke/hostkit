separate (Hostkit.Fs)
function Stat_Entry (Path : String; Follow_Links : Boolean; Want : Stat_Want) return Entry_Record is
   Info   : aliased Entry_Record;
   C_Path : Interfaces.C.Strings.chars_ptr;
   Status : C_Int;
   Error  : Integer;
begin
   if Path = "" or else (for some C of Path => C = ASCII.NUL) then
      raise Ada.Directories.Name_Error with "no entry at """ & Path & """";
   end if;
   C_Path := Interfaces.C.Strings.New_String (Path);
   Status := Stat_Call (C_Path, Follow_Links, Want, Info'Access);
   Error := GNAT.OS_Lib.Errno;
   Interfaces.C.Strings.Free (C_Path);
   if Status /= 0 then
      --  ENOENT and ENOTDIR: nothing there. ENAMETOOLONG only for a name
      --  no entry can bear; ELOOP only past a final link followed (it
      --  loops, as a dangling one points nowhere) -- on the way, or with
      --  the final link not followed, the host just will not say.
      if Error in Errno_Noent | Errno_Notdir
        or else (Error = Errno_Nametoolong and then Has_Overlong_Component (Path))
        or else (Error = Errno_Loop and then Follow_Links)
      then
         raise Ada.Directories.Name_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
      end if;
      raise Ada.Directories.Use_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
   elsif not Answered (Info, Want) then
      raise Ada.Directories.Use_Error with Path & ": the filesystem did not say";
   end if;
   return Info;
end Stat_Entry;
