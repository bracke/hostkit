separate (Hostkit_Suite)
procedure Test_An_Identity_Reads_Beside_Another_Reader
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Boot_Id : constant String := "/proc/sys/kernel/random/boot_id";
   Before  : constant String := Hostkit.Process.Identity_Of (1);
   Held    : Ada.Text_IO.File_Type;
begin
   if Before = "" or else not Ada.Directories.Exists (Boot_Id) then
      --  A host whose identities are not read from these files.
      Skip ("Test_An_Identity_Reads_Beside_Another_Reader", "process identities are not read from /proc here");
      return;
   end if;

   --  Another task reading the boot's id as this one asks: the run
   --  time refuses a second open of a file under its default form.
   Ada.Text_IO.Open (Held, Ada.Text_IO.In_File, Boot_Id);
   declare
      During : constant String := Hostkit.Process.Identity_Of (1);
   begin
      Ada.Text_IO.Close (Held);
      Assert (During = Before,
              "a process's identity was not read while another reader had the boot's id open: """
              & During & """");
   end;
end Test_An_Identity_Reads_Beside_Another_Reader;
