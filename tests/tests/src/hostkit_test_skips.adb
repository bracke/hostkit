with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Text_IO;

package body Hostkit_Test_Skips is

   Skipped : Natural := 0;
   Names   : Name_Vectors.Vector;

   procedure Skip (Test : String; Reason : String) is
      Item : constant String := Test & ": " & Reason;
   begin
      Skipped := Skipped + 1;
      if not Names.Contains (Item) then
         Names.Append (Item);
      end if;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "SKIP " & Item);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
   end Skip;

   function Skip_Count return Natural is (Skipped);

   function Has_Skipped (Item : String) return Boolean is (Names.Contains (Item));

   function Skips return Name_Vectors.Vector is (Names);

   function Matches_Expected return Boolean is
      List_Path : constant String := Ada.Environment_Variables.Value ("HOSTKIT_TEST_EXPECTED_SKIPS", "");
      Expected  : Name_Vectors.Vector;
      File      : Ada.Text_IO.File_Type;
      Agreed    : Boolean := True;
      --  A checkout that turned line ends into CR LF leaves the CR on.
      Blanks    : constant Ada.Strings.Maps.Character_Set :=
        Ada.Strings.Maps.To_Set (' ' & ASCII.HT & ASCII.CR);
   begin
      if List_Path = "" then
         return True;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, List_Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line    : constant String := Ada.Text_IO.Get_Line (File);
            Comment : constant Natural := Ada.Strings.Fixed.Index (Line, "--");
            Item    : constant String :=
              Ada.Strings.Fixed.Trim
                ((if Comment = 0 then Line else Line (Line'First .. Comment - 1)), Blanks, Blanks);
         begin
            if Item /= "" then
               Expected.Append (Item);
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      for Item of Names loop
         if not Expected.Contains (Item) then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "FAILED: skipped (" & Item & "), and " & List_Path & " does not list that skip");
            Agreed := False;
         end if;
      end loop;

      for Item of Expected loop
         if not Has_Skipped (Item) then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "FAILED: " & List_Path & " lists (" & Item
               & "), but no test skipped so: take it off the list, or give its reason now");
            Agreed := False;
         end if;
      end loop;

      return Agreed;
   end Matches_Expected;

end Hostkit_Test_Skips;
