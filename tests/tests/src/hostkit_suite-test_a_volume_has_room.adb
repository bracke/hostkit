separate (Hostkit_Suite)
procedure Test_A_Volume_Has_Room (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Capacity : constant Hostkit.Metadata.Volume_Capacity :=
     Hostkit.Metadata.Volume_Capacity_Of (Ada.Directories.Current_Directory);
begin
   Assert (Capacity.Available, "the volume this test is running on reports its capacity");
   Assert (Capacity.Capacity_Bytes > 0, "a mounted volume has a size");
   Assert
     (Capacity.Free_Bytes <= Capacity.Capacity_Bytes,
      "free space cannot exceed the volume it is free on");
   Assert
     (not Capacity.Inodes_Known or else Capacity.Free_Inode_Count <= Capacity.Inode_Count,
      "free inodes cannot exceed the inodes there are");
end Test_A_Volume_Has_Room;
