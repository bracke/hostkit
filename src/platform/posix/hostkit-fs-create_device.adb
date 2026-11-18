separate (Hostkit.Fs)
function Create_Device
  (Path   : String;
   Kind   : Device_Kind;
   Device : Interfaces.Unsigned_64;
   Mode   : Natural) return Boolean
is
   function C_Mknod
     (Path : Interfaces.C.Strings.chars_ptr;
      Mode : Interfaces.C.unsigned;
      Dev  : Interfaces.C.unsigned_long) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "mknod";

   S_IFCHR : constant Interfaces.C.unsigned := 8#020000#;
   S_IFBLK : constant Interfaces.C.unsigned := 8#060000#;

   C_Path : Interfaces.C.Strings.chars_ptr :=
     Interfaces.C.Strings.New_String (Path);
   Full   : constant Interfaces.C.unsigned :=
     (if Kind = Character_Device then S_IFCHR else S_IFBLK)
     or Interfaces.C.unsigned (Mode);
   Status : Interfaces.C.int;
begin
   Status :=
     C_Mknod (C_Path, Full, Interfaces.C.unsigned_long (Device));
   Interfaces.C.Strings.Free (C_Path);
   return Status = 0;
exception
   when others =>
      return False;
end Create_Device;
