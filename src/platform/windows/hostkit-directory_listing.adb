with Hostkit.Errors;
with Hostkit.Fs;
with Hostkit.Win32;
with Hostkit.Windows_Paths;
with Interfaces.C;
with System;

--  FindFirstFileW and FindNextFileW over Path\*, through the long form:
--  GNAT's Ada.Directories search refuses a folder past 260 characters, and
--  the folder could then not be listed at all. Each entry's attributes come
--  from the directory itself: a symbolic link or a junction (the reparse
--  tags Fs.Is_Link reads) is a link, any other entry a folder or a file by
--  its directory attribute -- a OneDrive placeholder is a reparse point too,
--  and an ordinary file or folder to its user.
package body Hostkit.Directory_Listing is
   use type Hostkit.Fs.Entry_Kind;

   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Error_File_Not_Found : constant C_DWord := 2;
   Error_No_More_Files  : constant C_DWord := 18;

   function List (Path : String; Entries : out Entry_Vectors.Vector) return Boolean is
      Data    : aliased Find_Data;
      Handle  : System.Address := Invalid_Handle_Value;
      Ignored : Interfaces.C.int;

      --  The entry Data holds, unless it is . or ..
      procedure Take is
         Length : Natural := 0;
      begin
         while Length < Data.File_Name'Last
           and then Data.File_Name (Length + 1) /= Wide_Character'Val (0)
         loop
            Length := Length + 1;
         end loop;
         declare
            Units : Wide_String (1 .. Length);
         begin
            for Index in Units'Range loop
               Units (Index) := Data.File_Name (Index);
            end loop;
            declare
               Name : constant String := Hostkit.Windows_Paths.To_UTF_8 (Units);
               Kind : constant Entry_Kind :=
                 (if (Data.Attributes and File_Attribute_Reparse_Point) /= 0
                    and then Is_Link_Tag (Data.Reparse_Tag)
                  then Symbolic_Link
                  elsif (Data.Attributes and File_Attribute_Directory) /= 0 then Directory
                  else Regular_File);
            begin
               if Name /= "." and then Name /= ".." then
                  Entries.Append (Listed_Entry'(Length => Name'Length, Kind => Kind, Name => Name));
               end if;
            end;
         end;
      end Take;
   begin
      Entries.Clear;
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return False;
      end if;
      declare
         Pattern : aliased constant Wide_String :=
           Hostkit.Windows_Paths.Native
             (Path & (if Path (Path'Last) in '\' | '/' then "" else "\") & "*");
      begin
         Handle := Find_First_File (Pattern'Address, Data'Access);
      end;
      if Handle = Invalid_Handle_Value then
         --  Nothing matched: a drive's root has no . and .. to list, so an
         --  empty one says so -- as does a path that is not there.
         if Get_Last_Error = Error_File_Not_Found
           and then Hostkit.Fs.Kind_Of (Path) = Hostkit.Fs.Directory_Entry
         then
            return True;
         end if;
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      loop
         Take;
         exit when Find_Next_File (Handle, Data'Access) = 0;
      end loop;
      declare
         Error : constant C_DWord := Get_Last_Error;
      begin
         if Error /= Error_No_More_Files then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         end if;
         Ignored := Find_Close (Handle);
         return Error = Error_No_More_Files;
      end;
   exception
      when others =>
         if Handle /= Invalid_Handle_Value then
            Ignored := Find_Close (Handle);
         end if;
         return False;
   end List;

end Hostkit.Directory_Listing;
