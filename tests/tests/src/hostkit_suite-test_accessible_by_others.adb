separate (Hostkit_Suite)
procedure Test_Accessible_By_Others (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   procedure Write (Path : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "key");
      Ada.Text_IO.Close (File);
   end Write;

   Secure : constant String := Ada.Directories.Compose (Scratch, "hk-key-0600");
   Open   : constant String := Ada.Directories.Compose (Scratch, "hk-key-0644");

   function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
     return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "chmod";

   procedure Chmod (Path : String; Mode : Interfaces.C.int) is
      C_Path  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Ignored : constant Interfaces.C.int := C_Chmod (C_Path, Mode);
   begin
      pragma Unreferenced (Ignored);
      Interfaces.C.Strings.Free (C_Path);
   end Chmod;
begin
   --  Only meaningful where mode bits mean something; on Windows this always answers False,
   --  and setting a POSIX mode there is a no-op, so there is nothing to assert.
   if not Hostkit.Shell.Is_Command_Shell then
      Write (Secure);
      Write (Open);
      Chmod (Secure, 8#600#);
      Chmod (Open, 8#644#);

      Assert
        (not Hostkit.Fs.Accessible_By_Others (Secure),
         "a 0600 file is not accessible by others");
      Assert
        (Hostkit.Fs.Accessible_By_Others (Open),
         "a 0644 file is accessible by others");
   end if;

   Assert
     (not Hostkit.Fs.Accessible_By_Others (Ada.Directories.Current_Directory),
      "a directory is not judged by this -- regular files only");
end Test_Accessible_By_Others;
