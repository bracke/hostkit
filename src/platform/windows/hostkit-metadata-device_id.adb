separate (Hostkit.Metadata)
function Device_Id
  (Path      : String;
   Available : out Boolean)
   return Long_Long_Integer
is
   Info : aliased By_Handle_File_Information;
begin
   Available := Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Missing_Entry;
   if not Available then
      return 0;
   elsif Followed_Information (Path, Info'Access) then
      return Long_Long_Integer (Info.Volume_Serial);
   elsif Hostkit.Fs.Is_Link (Path) then
      --  A link that leads nowhere (dangling, or a loop): Kind_Of sees
      --  the link itself, but the device is the target's, as POSIX's
      --  stat follows to it -- and there is none.
      Available := False;
      return 0;
   end if;

   declare
      C_Path    : aliased constant Wide_String := Wide (Path);
      Root      : aliased Wide_String (1 .. 32_768) := [others => Wide_Character'Val (0)];
      Serial    : aliased C_DWord := 0;
      Component : aliased C_DWord := 0;
      Flags     : aliased C_DWord := 0;
   begin
      if Get_Volume_Path_Name (C_Path'Address, Root'Address, Root'Length) /= 0
        and then Get_Volume_Information
                   (Root'Address, System.Null_Address, 0, Serial'Access, Component'Access, Flags'Access,
                    System.Null_Address, 0) /= 0
      then
         return Long_Long_Integer (Serial);
      end if;
   end;

   declare
      --  Absolute as text, GNAT's Full_Name refusing a path past 260
      --  characters, and in the form a caller writes rather than the long
      --  one, so a path given either way hashes alike.
      Absolute : constant String := Hostkit.Path_Text.Absolute (Path, Hostkit.Fs.Current_Directory);
      Plain    : constant String := Hostkit.Windows_Paths.Win32_Form (Absolute);
      Full     : constant String := Ada.Characters.Handling.To_Lower (Plain);
      Last : Natural := Full'First - 1;
      --  The 64-bit FNV-1a offset basis. The value only ever meets another
      --  read in the same process (no caller keeps it), so it was free to
      --  be corrected from a copy missing its last three digits.
      Hash : C_U64 := 14_695_981_039_346_656_037;
   begin
      if Full'Length >= 3
        and then Full (Full'First + 1) = ':'
        and then Full (Full'First + 2) in '\' | '/'
      then
         Last := Full'First + 1;
      elsif Full'Length >= 5
        and then Full (Full'First) in '\' | '/'
        and then Full (Full'First + 1) in '\' | '/'
      then
         Last := Full'First + 1;
         for I in Full'First + 2 .. Full'Last loop
            Last := I;
            exit when Full (I) in '\' | '/';
         end loop;
         if Last < Full'Last then
            for I in Last + 1 .. Full'Last loop
               Last := I;
               exit when Full (I) in '\' | '/';
            end loop;
         end if;
      else
         Last := Full'Last;
      end if;

      for I in Full'First .. Last loop
         Hash := (Hash xor C_U64 (Character'Pos (Full (I)))) * 1_099_511_628_211;
      end loop;
      return Long_Long_Integer (Hash mod C_U64 (Long_Long_Integer'Last));
   end;
exception
   when others =>
      Available := False;
      return 0;
end Device_Id;
