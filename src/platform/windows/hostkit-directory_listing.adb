with Ada.Strings.UTF_Encoding.Conversions;

with Hostkit.Fs;
with Hostkit.Windows_Paths;
with Interfaces.C;
with System;
with System.Storage_Elements;

--  FindFirstFileW and FindNextFileW over Path\*, through the long form:
--  GNAT's Ada.Directories search refuses a folder past 260 characters, and
--  the folder could then not be listed at all. Each entry's attributes come
--  from the directory itself: a symbolic link or a junction (the reparse
--  tags Fs.Is_Link reads) is a link, any other entry a folder or a file by
--  its directory attribute -- a OneDrive placeholder is a reparse point too,
--  and an ordinary file or folder to its user.
package body Hostkit.Directory_Listing is
   use type Hostkit.Fs.Entry_Kind;

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   type File_Time is record
      Low  : C_DWord;
      High : C_DWord;
   end record with Convention => C;

   type Wide_Name is array (1 .. 260) of Wide_Character with Convention => C;
   type Short_Name is array (1 .. 14) of Wide_Character with Convention => C;

   --  WIN32_FIND_DATAW; Reserved_0 is the reparse tag of a reparse point.
   type Find_Data is record
      Attributes     : C_DWord;
      Creation_Time  : File_Time;
      Access_Time    : File_Time;
      Write_Time     : File_Time;
      Size_High      : C_DWord;
      Size_Low       : C_DWord;
      Reserved_0     : C_DWord;
      Reserved_1     : C_DWord;
      File_Name      : Wide_Name;
      Alternate_Name : Short_Name;
   end record with Convention => C;

   Attribute_Directory     : constant C_DWord := 16#10#;
   Attribute_Reparse_Point : constant C_DWord := 16#400#;
   Tag_Symlink             : constant C_DWord := 16#A000_000C#;
   Tag_Mount_Point         : constant C_DWord := 16#A000_0003#;
   Error_File_Not_Found    : constant C_DWord := 2;
   Error_No_More_Files     : constant C_DWord := 18;
   Invalid_Handle          : constant System.Address :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);

   function Find_First_File (Name : System.Address; Data : access Find_Data) return System.Address
     with Import, Convention => Stdcall, External_Name => "FindFirstFileW";
   function Find_Next_File (Handle : System.Address; Data : access Find_Data) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "FindNextFileW";
   function Find_Close (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "FindClose";
   function Get_Last_Error return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLastError";

   function List (Path : String; Entries : out Entry_Vectors.Vector) return Boolean is
      Data    : aliased Find_Data;
      Handle  : System.Address := Invalid_Handle;
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
               Name : constant String := Ada.Strings.UTF_Encoding.Conversions.Convert (Units);
               Kind : constant Entry_Kind :=
                 (if (Data.Attributes and Attribute_Reparse_Point) /= 0
                    and then Data.Reserved_0 in Tag_Symlink | Tag_Mount_Point
                  then Symbolic_Link
                  elsif (Data.Attributes and Attribute_Directory) /= 0 then Directory
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
      if Handle = Invalid_Handle then
         --  Nothing matched: a drive's root has no . and .. to list, so an
         --  empty one says so -- as does a path that is not there.
         return Get_Last_Error = Error_File_Not_Found
           and then Hostkit.Fs.Kind_Of (Path) = Hostkit.Fs.Directory_Entry;
      end if;
      loop
         Take;
         exit when Find_Next_File (Handle, Data'Access) = 0;
      end loop;
      declare
         Error : constant C_DWord := Get_Last_Error;
      begin
         Ignored := Find_Close (Handle);
         return Error = Error_No_More_Files;
      end;
   exception
      when others =>
         if Handle /= Invalid_Handle then
            Ignored := Find_Close (Handle);
         end if;
         return False;
   end List;

end Hostkit.Directory_Listing;
