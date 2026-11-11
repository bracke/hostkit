separate (Hostkit_Suite)
procedure Test_Metadata_Reports_What_It_Could_Not_Get
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Missing   : constant String := Ada.Directories.Compose (Scratch, "hk-no-such-file-xyzzy");
   Mode      : Natural;
   Available : Boolean;
   User_Id   : Natural;
   Group_Id  : Natural;
   Born      : Ada.Calendar.Time;
   pragma Unreferenced (Born);
begin
   --  The contract that keeps a caller from inventing facts: a path this host
   --  cannot answer for reports Available => False, and the value that comes
   --  back with it is not a fact about any file.
   Mode := Hostkit.Metadata.File_Permission_Bits (Missing, Available);
   Assert (not Available, "a missing file has no permission bits to report");
   Assert (Mode = 0, "and the accompanying value is the neutral 0, not a mode");

   Hostkit.Metadata.File_Ownership (Missing, User_Id, Group_Id, Available);
   Assert (not Available, "a missing file has no ownership to report");

   Born := Hostkit.Metadata.File_Creation_Time (Missing, Available);
   Assert (not Available, "a missing file has no creation time to report");

   Assert
     (not Hostkit.Metadata.Volume_Capacity_Of (Missing & "/deeper").Available
        or else True,
      "asking about a volume that is not there does not raise");
end Test_Metadata_Reports_What_It_Could_Not_Get;
