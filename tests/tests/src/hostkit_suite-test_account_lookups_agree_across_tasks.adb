separate (Hostkit_Suite)
procedure Test_Account_Lookups_Agree_Across_Tasks
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Account_Id;
   Path      : constant String := Ada.Directories.Compose (Scratch, "hk-meta-lookups");
   User_Id   : Hostkit.Metadata.Account_Id;
   Group_Id  : Hostkit.Metadata.Account_Id;
   Available : Boolean;
begin
   --  Windows has no uid/gid pair (Test_A_Name_Round_Trips_Through_Its_Id).
   if not Hostkit.Metadata.Ownership_Supported then
      return;
   end if;

   Write_File (Path, "x");
   Hostkit.Metadata.File_Ownership (Path, User_Id, Group_Id, Available);
   Ada.Directories.Delete_File (Path);
   Assert (Available, "a file this process just created has ownership to report");

   declare
      User_Name  : constant String := Hostkit.Metadata.User_Name_For_Id (User_Id);
      Group_Name : constant String := Hostkit.Metadata.Group_Name_For_Id (Group_Id);
      Workers    : constant := 8;
      Rounds     : constant := 200;
      Wrong      : array (1 .. Workers) of Natural := [others => 0];
      Found      : Boolean;
   begin
      Assert (User_Name /= "", "the owning user id resolves to a name");
      Assert (Hostkit.Metadata.User_Id_For_Name (User_Name, Found) = User_Id and then Found,
              "and back to its id");
      if Group_Name /= "" then
         Assert (Hostkit.Metadata.Group_Id_For_Name (Group_Name, Found) = Group_Id and then Found,
                 "the owning group resolves back to its id");
      end if;
      Assert (Hostkit.Metadata.User_Id_For_Name ("hostkit-no-such-user-x", Found) = Hostkit.Metadata.Account_Id'(0)
                and then not Found,
              "an unknown user is not found");
      Assert (Hostkit.Metadata.Group_Id_For_Name ("hostkit-no-such-group-x", Found) = Hostkit.Metadata.Account_Id'(0)
                and then not Found,
              "an unknown group is not found");

      --  Lookups on several tasks at once: each answer is its own. With the
      --  C library's static buffer a lookup on one task could overwrite the
      --  name another was still reading.
      declare
         task type Worker is
            entry Go (Index : Positive);
         end Worker;

         task body Worker is
            Mine  : Positive;
            Found : Boolean;
         begin
            accept Go (Index : Positive) do
               Mine := Index;
            end Go;
            for Round in 1 .. Rounds loop
               if Hostkit.Metadata.User_Name_For_Id (User_Id) /= User_Name
                 or else Hostkit.Metadata.User_Id_For_Name (User_Name, Found) /= User_Id
                 or else not Found
                 or else Hostkit.Metadata.Group_Name_For_Id (Group_Id) /= Group_Name
                 or else (Round mod 2 = 0
                          and then Hostkit.Metadata.User_Id_For_Name ("hostkit-no-such-user-x", Found)
                            /= Hostkit.Metadata.Account_Id'(0))
               then
                  Wrong (Mine) := Wrong (Mine) + 1;
               end if;
            end loop;
         end Worker;

         Crew : array (1 .. Workers) of Worker;
      begin
         for Index in Crew'Range loop
            Crew (Index).Go (Index);
         end loop;
      end;

      for Index in Wrong'Range loop
         Assert (Wrong (Index) = 0, "task" & Index'Image & " read a wrong answer" & Wrong (Index)'Image & " times");
      end loop;
   end;
end Test_Account_Lookups_Agree_Across_Tasks;
