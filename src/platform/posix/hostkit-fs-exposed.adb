separate (Hostkit.Fs)
function Exposed (Path : String; Want : Ada.Directories.File_Kind) return Boolean is
   use type Interfaces.Unsigned_8;
   use type Ada.Directories.File_Kind;

   --  struct stat is larger than this; stat writes only into what it needs and the mode
   --  sits near the front. Oversized so there is always room.
   Buffer : array (0 .. 255) of aliased Interfaces.Unsigned_8 := [others => 0];

   function C_Stat (Path : Interfaces.C.Strings.chars_ptr; Buf : System.Address)
     return Interfaces.C.int
     with Import => True, Convention => C, External_Name => Stat_Symbol;

   C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
   Result : Interfaces.C.int;
begin
   if not Ada.Directories.Exists (Path)
     or else Ada.Directories.Kind (Path) /= Want
   then
      Interfaces.C.Strings.Free (C_Path);
      return False;
   end if;

   Result := C_Stat (C_Path, Buffer'Address);
   Interfaces.C.Strings.Free (C_Path);

   if Result /= 0 then
      return False;
   end if;

   --  st_mode's low byte holds the group and other permission bits. Its offset in the
   --  struct is Mode_Low_Byte on this platform's LP64 layout.
   return (Buffer (Mode_Low_Byte) and 8#077#) /= 0;
exception
   when others =>
      return False;
end Exposed;
