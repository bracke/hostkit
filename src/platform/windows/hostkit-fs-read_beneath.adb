with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Wide_Unbounded;

--  Read Path beneath Root, each part held open in turn and refused when it
--  is a link or junction, so nothing outside Root can be read through it.
separate (Hostkit.Fs)
procedure Read_Beneath
  (Root    : String;
   Path    : String;
   Most    : Natural;
   Text    : out Ada.Strings.Unbounded.Unbounded_String;
   Outcome : out Read_Beneath_Outcome)
is
   use type System.Address;

   package Part_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   package Handle_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => System.Address);

   --  A data right: a handle holding only attribute rights takes no part
   --  in the sharing check, so the folder it held could still be renamed
   --  away and a link put in its place while the walk went on below it.
   File_List_Directory  : constant C_DWord := 16#01#;
   --  Read and write, never delete: a directory held so cannot be
   --  renamed or replaced while the walk goes on below it.
   Share_No_Delete      : constant C_DWord := 3;
   Backup_Semantics     : constant C_DWord := 16#0200_0000#;
   Open_Reparse_Point   : constant C_DWord := 16#0020_0000#;
   Error_File_Not_Found : constant C_DWord := 2;
   Error_Path_Not_Found : constant C_DWord := 3;
   Chunk                : constant := 65_536;

   Held  : Handle_Vectors.Vector;
   Parts : Part_Vectors.Vector;
   Start : Positive := Path'First;

   procedure Let_Go is
      Ignored : Interfaces.C.int;
   begin
      for Handle of Held loop
         Ignored := Close_Handle (Handle);
      end loop;
      Held.Clear;
   end Let_Go;

   function Open (Name : Wide_String; Access_Mode, Flags : C_DWord) return System.Address is
      Terminated : aliased constant Wide_String := Name & Wide_Character'Val (0);
   begin
      return Create_File
        (Terminated'Address, Access_Mode, Share_No_Delete, System.Null_Address, Open_Existing, Flags,
         System.Null_Address);
   end Open;
begin
   Text := Ada.Strings.Unbounded.Null_Unbounded_String;
   Outcome := Read_Failed;
   if Path'Length = 0 or else Path (Path'First) in '/' | '\' then
      Outcome := Read_Outside;
      return;
   end if;
   for Index in Path'First .. Path'Last + 1 loop
      if Index > Path'Last or else Path (Index) in '/' | '\' then
         declare
            Part : constant String := Path (Start .. Index - 1);
         begin
            if Part = ".." or else (for some C of Part => C in ':' | ASCII.NUL) then
               Outcome := Read_Outside;
               return;
            elsif Part /= "" and then Part /= "." then
               Parts.Append (Part);
            end if;
         end;
         Start := Index + 1;
      end if;
   end loop;
   if Parts.Is_Empty then
      Outcome := Read_Not_File;
      return;
   end if;

   --  Root, links and all, held and named as it resolves: every part
   --  below is named from there. Root in the long form, without the
   --  terminator Open adds itself.
   declare
      Native_Root : constant Wide_String := Wide (if Root = "" then "." else Root);
      Root_Handle : constant System.Address :=
        Open (Native_Root (Native_Root'First .. Native_Root'Last - 1), File_Read_Attributes + File_List_Directory,
              Backup_Semantics);
   begin
      if Root_Handle = Invalid_Handle_Value then
         Outcome := Read_Missing;
         return;
      end if;
      Held.Append (Root_Handle);
   end;
   declare
      Length : constant C_DWord := Get_Final_Path_Name (Held.First_Element, System.Null_Address, 0, 0);
   begin
      if Length = 0 then
         Let_Go;
         return;
      end if;
      declare
         Buffer  : aliased Wide_String (1 .. Natural (Length) + 1);
         Written : constant C_DWord := Get_Final_Path_Name (Held.First_Element, Buffer'Address, Length + 1, 0);
         Current : Ada.Strings.Wide_Unbounded.Unbounded_Wide_String;
         Handle  : System.Address := Invalid_Handle_Value;
         Info    : aliased By_Handle_File_Information;
      begin
         if Written = 0 or else Written > Length then
            Let_Go;
            return;
         end if;
         Current := Ada.Strings.Wide_Unbounded.To_Unbounded_Wide_String (Buffer (1 .. Natural (Written)));
         for Index in Parts.First_Index .. Parts.Last_Index loop
            declare
               Last : constant Boolean := Index = Parts.Last_Index;
            begin
               Ada.Strings.Wide_Unbounded.Append
                 (Current, "\" & Hostkit.Windows_Paths.From_UTF_8 (Parts (Index)));
               --  The part as itself: a link or junction is opened, not
               --  what it points at, and refused below.
               Handle := Open
                 (Ada.Strings.Wide_Unbounded.To_Wide_String (Current),
                  File_Read_Attributes + (if Last then Generic_Read else File_List_Directory),
                  Backup_Semantics + Open_Reparse_Point);
               if Handle = Invalid_Handle_Value then
                  Outcome :=
                    (if Get_Last_Error in Error_File_Not_Found | Error_Path_Not_Found then Read_Missing
                     else Read_Failed);
                  Let_Go;
                  return;
               end if;
               Held.Append (Handle);
               if Get_File_Information (Handle, Info'Access) = 0 then
                  Let_Go;
                  return;
               elsif (Info.Attributes and File_Attribute_Reparse_Point) /= 0 then
                  Outcome := Read_Outside;
                  Let_Go;
                  return;
               elsif Last = ((Info.Attributes and File_Attribute_Directory) /= 0) then
                  Outcome := (if Last then Read_Not_File else Read_Missing);
                  Let_Go;
                  return;
               end if;
            end;
         end loop;
         if Info.Size_High /= 0 or else Long_Long_Integer (Info.Size_Low) > Long_Long_Integer (Most) then
            Outcome := Read_Too_Large;
            Let_Go;
            return;
         end if;
         declare
            Chunk_Of : aliased String (1 .. Chunk);
            Got      : aliased C_DWord;
            Total    : Natural := 0;
         begin
            loop
               if Read_File (Handle, Chunk_Of'Address, Chunk, Got'Access, System.Null_Address) = 0 then
                  exit;
               elsif Got = 0 then
                  Outcome := Read_Done;
                  exit;
               elsif Natural (Got) > Most - Total then
                  Outcome := Read_Too_Large;
                  exit;
               end if;
               Total := Total + Natural (Got);
               Ada.Strings.Unbounded.Append (Text, Chunk_Of (1 .. Natural (Got)));
            end loop;
         end;
      end;
   end;
   Let_Go;
   if Outcome /= Read_Done then
      Text := Ada.Strings.Unbounded.Null_Unbounded_String;
   end if;
exception
   when others =>
      Let_Go;
      Text := Ada.Strings.Unbounded.Null_Unbounded_String;
      Outcome := Read_Failed;
end Read_Beneath;
