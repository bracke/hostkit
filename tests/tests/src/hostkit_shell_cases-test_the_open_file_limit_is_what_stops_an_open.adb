separate (Hostkit_Shell_Cases)
procedure Test_The_Open_File_Limit_Is_What_Stops_An_Open
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   use type Hostkit.Host.Kind;
   use type Hostkit.Limits.Amount;

   Lowered : constant Hostkit.Limits.Amount := 16;

   Was     : Hostkit.Limits.Amount;
   Opened  : Natural := 0;
   Refused : Boolean := False;
   Put_Back : Boolean := False;
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      --  No limits to lower; the case above says so.
      Skip ("Test_The_Open_File_Limit_Is_What_Stops_An_Open", "Windows has no open-file limit to lower");
      return;
   end if;

   Assert (Hostkit.Limits.Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Was),
           "the open-file limit can be read");

   declare
      Room : constant String :=
        Hostkit.Fs.Create_Temporary_Directory ("hostkit-limit-test");

      Held : array (1 .. 64) of Ada.Text_IO.File_Type;
   begin
      if Hostkit.Limits.Set_Limit
           (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Lowered)
      then
         for Index in Held'Range loop
            begin
               Ada.Text_IO.Create
                 (Held (Index), Ada.Text_IO.Out_File,
                  Hostkit.Fs.Join
                    (Room,
                     "f" & Ada.Strings.Fixed.Trim
                             (Integer'Image (Index), Ada.Strings.Both)));
               Opened := Opened + 1;
            exception
               when others =>
                  Refused := True;
                  exit;
            end;
         end loop;

         for Index in 1 .. Opened loop
            Ada.Text_IO.Close (Held (Index));
         end loop;

         Put_Back :=
           Hostkit.Limits.Set_Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Was);
      end if;

      Ada.Directories.Delete_Tree (Room);
   end;

   Assert (Put_Back,
           "the open-file limit was lowered and put back");
   Assert (Refused,
           "a lowered open-file limit refuses an open;"
           & Natural'Image (Opened) & " files opened under a limit of"
           & Hostkit.Limits.Amount'Image (Lowered));
end Test_The_Open_File_Limit_Is_What_Stops_An_Open;
