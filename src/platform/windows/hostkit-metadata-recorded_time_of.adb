separate (Hostkit.Metadata)
function Recorded_Time_Of
  (Path      : String;
   Which     : Recorded_Time;
   Available : out Boolean) return Ada.Calendar.Time
is
   C_Path : aliased Wide_String := Wide (Path);
   Data   : aliased Attribute_Data;
   Result : C_Int;
   --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
   --  midnight and shift every time by the zone's 1970 offset.
   Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
begin
   Available := False;

   Result := Get_File_Attributes_Ex (C_Path'Address, 0, Data'Access);

   if Result = 0 then
      return Ada.Calendar.Time_Of (1901, 1, 1);
   end if;

   declare
      Stamp : constant Filetime :=
        (case Which is
            when Creation    => Data.Creation_Time,
            when Last_Access => Data.Access_Time);
      --  FILETIME counts 100-nanosecond ticks from 1601; Unix time starts
      --  11644473600 seconds later.
      Ticks : constant C_U64 := C_U64 (Stamp.High) * 2 ** 32 + C_U64 (Stamp.Low);
      Unix  : constant Long_Long_Integer :=
        Long_Long_Integer (Ticks / 10_000_000) - 11_644_473_600;
   begin
      if Unix <= 0 then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      Available := True;
      return Epoch + Duration (Unix);
   end;

exception
   when others =>
      Available := False;
      return Ada.Calendar.Time_Of (1901, 1, 1);
end Recorded_Time_Of;
