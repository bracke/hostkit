separate (Hostkit.Metadata)
function Volume_Capacity_Of (Path : String) return Volume_Capacity is
   C_Path : aliased Wide_String := Wide (Path);

   Free_To_Caller : aliased C_U64 := 0;
   Total          : aliased C_U64 := 0;
   Total_Free     : aliased C_U64 := 0;

   Serial    : aliased C_DWord := 0;
   Component : aliased C_DWord := 0;
   Flags     : aliased C_DWord := 0;

   Answer : Volume_Capacity;
   Result : C_Int;
begin
   Result :=
     Get_Disk_Free_Space_Ex
       (C_Path'Address, Free_To_Caller'Access, Total'Access, Total_Free'Access);

   if Result /= 0 then
      Answer.Available := True;
      Answer.Capacity_Bytes := Long_Long_Integer (Total);
      Answer.Free_Bytes := Long_Long_Integer (Free_To_Caller);
   end if;

   --  Windows keeps no inode count; the name limit and the read-only flag come
   --  from the volume rather than the file -- and GetVolumeInformation insists
   --  on the volume's ROOT, "C:\", not a directory anywhere inside it. Handed
   --  a path like C:\Users\... it simply fails, and the read-only flag and the
   --  name limit were reported as unknown for every volume. GetVolumePathNameW
   --  finds that root from the long form, as Fs.On_Network_Volume does: a
   --  drive's, a share's (\\server\share\) or that of a volume mounted on a
   --  folder, whose root is the folder, not the drive holding it.
   declare
      Root : aliased Wide_String (1 .. 32_768) := [others => Wide_Character'Val (0)];
   begin
      Result :=
        (if Get_Volume_Path_Name (C_Path'Address, Root'Address, Root'Length) = 0 then 0
         else
           Get_Volume_Information
             (Root'Address,
              System.Null_Address, 0,
              Serial'Access, Component'Access, Flags'Access,
              System.Null_Address, 0));
   end;

   if Result /= 0 then
      Answer.Name_Max := Natural (Component);
      Answer.Name_Max_Known := True;
      Answer.Read_Only := (Flags and Read_Only_Volume) /= 0;
      Answer.Read_Only_Known := True;
   end if;

   return Answer;

exception
   when others =>
      return (others => <>);
end Volume_Capacity_Of;
