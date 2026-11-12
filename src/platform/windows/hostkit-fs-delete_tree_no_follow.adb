with Ada.Containers.Indefinite_Vectors;

--  Delete Path and everything under it without following a link, through
--  handles held open with delete access: each child is opened by the
--  name its held folder resolves to and checked to be the entry listed.
separate (Hostkit.Fs)
function Delete_Tree_No_Follow (Path : String) return Delete_Tree_Outcome is
   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.C.unsigned_short;
   use type System.Address;

   subtype C_U16 is Interfaces.C.unsigned_short;
   type U16_Array is array (Natural range <>) of aliased C_U16
     with Convention => C;
   type Byte_Array is array (Natural range <>) of aliased Interfaces.Unsigned_8
     with Convention => C;
   type Directory_Header is record
      Next_Offset : Interfaces.Unsigned_32;
      Name_Length : Interfaces.Unsigned_32;
      File_Id     : Interfaces.Unsigned_64;
   end record;
   for Directory_Header use record
      Next_Offset at 0 range 0 .. 31;
      Name_Length at 60 range 0 .. 31;
      File_Id     at 96 range 0 .. 63;
   end record;
   for Directory_Header'Size use 104 * 8;
   type Disposition_Info is record
      Delete_File : Interfaces.C.int;
   end record with Convention => C;
   type Disposition_Info_Ex is record
      Flags : C_DWord;
   end record with Convention => C;
   type Child (Length : Natural) is record
      Name : U16_Array (1 .. Length);
      Id   : Interfaces.Unsigned_64;
   end record;
   package Child_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Child);

   Max_Depth : constant := 2_048;
   Max_Entries : constant := 100_000;
   Max_Name_Bytes : constant := 64 * 1_024 * 1_024;
   Delete_Access : constant C_DWord := 16#0001_0000#;
   File_List_Directory : constant C_DWord := 1;
   Share_All : constant C_DWord := 7;
   Backup_Semantics : constant C_DWord := 16#0200_0000#;
   Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
   Id_Both_Directory_Info : constant Interfaces.C.int := 10;
   Id_Both_Directory_Restart_Info : constant Interfaces.C.int := 11;
   File_Disposition_Info : constant Interfaces.C.int := 4;
   File_Disposition_Info_Ex : constant Interfaces.C.int := 21;
   --  FILE_DISPOSITION_FLAG_DELETE, _POSIX_SEMANTICS and
   --  _IGNORE_READONLY_ATTRIBUTE: a read-only file (git marks its objects
   --  so) is deleted like any other, as it is on POSIX hosts.
   Disposition_Delete_Flags : constant C_DWord := 16#1# + 16#2# + 16#10#;
   Error_No_More_Files : constant C_DWord := 18;
   --  Errors for a refusal no Win32 call reported, put into errno through
   --  Hostkit.Windows_Errors: the entry opened is not the one listed
   --  (ENOENT), a listing that does not parse (EIO).
   Error_File_Not_Found : constant Interfaces.Unsigned_32 := 2;
   Error_Io_Device : constant Interfaces.Unsigned_32 := 1117;

   function Set_File_Information
     (Handle : System.Address; Kind : Interfaces.C.int;
      Info : System.Address; Size : C_DWord) return Interfaces.C.int
     with Import, Convention => Stdcall,
          External_Name => "SetFileInformationByHandle";

   --  Name opened to be deleted, never followed. Listing is asked for as
   --  well, for a folder to be emptied; an entry whose own DACL refuses
   --  reading (a mode-0 file) is opened again without it, since deleting
   --  needs no read: its folder's FILE_DELETE_CHILD grants the DELETE,
   --  as a POSIX folder's write bit lets an unreadable file go.
   --  Writing the attributes is asked for too, where granted, so that a
   --  read-only file can be let go on a volume without
   --  FILE_DISPOSITION_FLAG_IGNORE_READONLY_ATTRIBUTE (FAT, exFAT).
   function Open_For_Delete (Name : System.Address) return System.Address is
      Error_Access_Denied : constant C_DWord := 5;
      Handle : System.Address := Create_File
        (Name, Delete_Access + File_Read_Attributes + File_Write_Attributes + File_List_Directory,
         Share_All, System.Null_Address, Open_Existing,
         Backup_Semantics + Open_Reparse_Point, System.Null_Address);
   begin
      if Handle = Invalid_Handle_Value and then Get_Last_Error = Error_Access_Denied then
         Handle := Create_File
           (Name, Delete_Access + File_Read_Attributes + File_List_Directory,
            Share_All, System.Null_Address, Open_Existing,
            Backup_Semantics + Open_Reparse_Point, System.Null_Address);
      end if;
      if Handle = Invalid_Handle_Value and then Get_Last_Error = Error_Access_Denied then
         Handle := Create_File
           (Name, Delete_Access + File_Read_Attributes,
            Share_All, System.Null_Address, Open_Existing,
            Backup_Semantics + Open_Reparse_Point, System.Null_Address);
      end if;
      return Handle;
   end Open_For_Delete;

   Read_Only_Attribute : constant C_DWord := 16#0000_0001#;

   --  Set the attributes of the entry held as Held, leaving its times as
   --  they are: False where they cannot be set.
   function Set_Attributes (Held : System.Address; Attributes : C_DWord) return Boolean is
      --  FILE_BASIC_INFO: 40 bytes, its DWORD padded to the next 8.
      type Basic_Info is record
         Creation, Last_Access, Last_Write, Change : Interfaces.Integer_64;
         Attributes : C_DWord;
         Padding    : C_DWord := 0;
      end record with Convention => C;
      pragma Compile_Time_Error (Basic_Info'Size /= 40 * 8, "Win32 FILE_BASIC_INFO must be 40 bytes");
      Normal_Attribute    : constant C_DWord := 16#0000_0080#;
      File_Basic_Info     : constant Interfaces.C.int := 0;
      --  Zero times leave each time as it is; no attributes at all is
      --  FILE_ATTRIBUTE_NORMAL, as zero would leave them unchanged.
      Basic : aliased Basic_Info :=
        (0, 0, 0, 0, (if Attributes = 0 then Normal_Attribute else Attributes), 0);
   begin
      return Set_File_Information (Held, File_Basic_Info, Basic'Address, C_DWord (Basic_Info'Size / 8)) /= 0;
   end Set_Attributes;

   --  Drop the read-only attribute of the entry held as Held, keeping
   --  the others: False where it has none or it cannot be dropped.
   function Drop_Read_Only (Held : System.Address; Info : By_Handle_File_Information) return Boolean is
     ((Info.Attributes and Read_Only_Attribute) /= 0
      and then Set_Attributes (Held, Info.Attributes and not Read_Only_Attribute));

   function File_Index (Info : By_Handle_File_Information) return Interfaces.Unsigned_64 is
     (Interfaces.Unsigned_64 (Info.File_Index_High) * 2 ** 32
      + Interfaces.Unsigned_64 (Info.File_Index_Low));

   --  Read Directory's children from its start. Full is True when
   --  Max_Entries were read and more may follow: the caller deletes those,
   --  then reads again, so a folder of any size is deleted in batches.
   function Read_Children
     (Directory : System.Address; Items : in out Child_Vectors.Vector; Full : out Boolean)
      return Boolean
   is
      --  FILE_ID_BOTH_DIR_INFO holds LARGE_INTEGERs, and each record is
      --  read in place through Directory_Header: the buffer is aligned for
      --  them, as the records in it are by their offsets.
      Buffer : aliased Byte_Array (0 .. 65_535) with Alignment => 8;
      Kind : Interfaces.C.int := Id_Both_Directory_Restart_Info;
      Name_Bytes : Natural := 0;
   begin
      Full := False;
      loop
         if Get_File_Information_Ex
           (Directory, Kind, Buffer'Address, C_DWord (Buffer'Length)) = 0
         then
            declare
               Error : constant C_DWord := Get_Last_Error;
            begin
               if Error = Error_No_More_Files then
                  return True;
               end if;
               Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Error));
               return False;
            end;
         end if;
         Kind := Id_Both_Directory_Info;
         declare
            Offset : Natural := 0;
         begin
            loop
               declare
                  Header : Directory_Header
                    with Import, Address => Buffer (Offset)'Address;
                  Length : constant Natural := Natural (Header.Name_Length) / 2;
                  Item : Child (Length);
                  Dot : Boolean := False;
               begin
                  if Offset + 104 + Natural (Header.Name_Length) > Buffer'Length then
                     Hostkit.Windows_Errors.Set_Errno_From (Error_Io_Device);
                     return False;
                  end if;
                  for Index in 1 .. Length loop
                     declare
                        Unit : C_U16 with Import,
                          Address => Buffer (Offset + 104 + (Index - 1) * 2)'Address;
                     begin
                        Item.Name (Index) := Unit;
                     end;
                  end loop;
                  Dot := (Length = 1 and then Item.Name (1) = Character'Pos ('.'))
                    or else (Length = 2 and then Item.Name (1) = Character'Pos ('.')
                             and then Item.Name (2) = Character'Pos ('.'));
                  if not Dot then
                     if Natural (Items.Length) >= Max_Entries
                       or else Natural (Header.Name_Length) > Max_Name_Bytes - Name_Bytes
                     then
                        Full := True;
                        return True;
                     end if;
                     Item.Id := Header.File_Id;
                     Items.Append (Item);
                     Name_Bytes := Name_Bytes + Natural (Header.Name_Length);
                  end if;
                  exit when Header.Next_Offset = 0;
                  if Natural (Header.Next_Offset) > Buffer'Length - Offset then
                     Hostkit.Windows_Errors.Set_Errno_From (Error_Io_Device);
                     return False;
                  end if;
                  Offset := Offset + Natural (Header.Next_Offset);
               end;
            end loop;
         end;
      end loop;
   exception
      when others =>
         Hostkit.Windows_Errors.Set_Errno_From (Error_Io_Device);
         return False;
   end Read_Children;

   function Child_Path (Parent : System.Address; Name : U16_Array) return U16_Array is
      Length : constant C_DWord := Get_Final_Path_Name
        (Parent, System.Null_Address, 0, 0);
   begin
      if Length = 0 then
         return [1 .. 0 => 0];
      end if;
      declare
         Result : U16_Array (0 .. Natural (Length) + Name'Length + 1) := [others => 0];
         Written : constant C_DWord := Get_Final_Path_Name
           (Parent, Result'Address, Length + 1, 0);
         Next : Natural := Natural (Written);
      begin
         if Written = 0 or else Written > Length then
            return [1 .. 0 => 0];
         end if;
         if Next > 0 and then Result (Next - 1) /= Character'Pos ('\') then
            Result (Next) := Character'Pos ('\');
            Next := Next + 1;
         end if;
         for Unit of Name loop
            Result (Next) := Unit;
            Next := Next + 1;
         end loop;
         Result (Next) := 0;
         return Result (0 .. Next);
      end;
   end Child_Path;

   --  Whether the held entry is a link to leave alone rather than a
   --  folder to empty: only the symbolic-link and junction tags are
   --  (Hostkit.Win32.Is_Held_Link). A OneDrive placeholder folder is a
   --  reparse point too, and its contents are the user's. An unreadable tag
   --  counts as a link: the link itself is deleted, never what it names.
   function Holds_Link (Held : System.Address; Info : By_Handle_File_Information) return Boolean is
      Ignored : C_DWord;
   begin
      return Is_Held_Link (Held, Info.Attributes, Ignored);
   end Holds_Link;

   function Delete_Held (Held : System.Address; Depth : Natural) return Boolean is
      Info : aliased By_Handle_File_Information;
      Items : Child_Vectors.Vector;
      Ok : Boolean := Depth <= Max_Depth
        and then Get_File_Information (Held, Info'Access) /= 0;
      Full : Boolean := True;
      Ignored : Interfaces.C.int;
   begin
      if not Ok and then Depth <= Max_Depth then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      if Ok and then (Info.Attributes and File_Attribute_Directory) /= 0
        and then not Holds_Link (Held, Info)
      then
         while Ok and then Full loop
            Items.Clear;
            Ok := Read_Children (Held, Items, Full);
            for Item of Items loop
               exit when not Ok;
               declare
                  Name : constant U16_Array := Child_Path (Held, Item.Name);
                  Child_Handle : System.Address :=
                    (if Name'Length = 0 then Invalid_Handle_Value else Open_For_Delete (Name'Address));
                  Child_Info : aliased By_Handle_File_Information;
               begin
                  if Child_Handle = Invalid_Handle_Value and then Name'Length /= 0 then
                     Hostkit.Errors.Set_Errno_From_Last_Error;
                  end if;
                  Ok := Child_Handle /= Invalid_Handle_Value
                    and then Get_File_Information (Child_Handle, Child_Info'Access) /= 0;
                  if not Ok and then Child_Handle /= Invalid_Handle_Value then
                     Hostkit.Errors.Set_Errno_From_Last_Error;
                  elsif Ok
                    and then (Child_Info.Volume_Serial /= Info.Volume_Serial
                              or else File_Index (Child_Info) /= Item.Id)
                  then
                     --  Another entry than the one listed is at the name now.
                     Ok := False;
                     Hostkit.Windows_Errors.Set_Errno_From (Error_File_Not_Found);
                  end if;
                  if Ok then
                     Ok := Delete_Held (Child_Handle, Depth + 1);
                     Child_Handle := Invalid_Handle_Value;
                  elsif Child_Handle /= Invalid_Handle_Value then
                     Ignored := Close_Handle (Child_Handle);
                  end if;
               end;
            end loop;
         end loop;
      end if;
      if Ok then
         declare
            Disposition_Ex : aliased Disposition_Info_Ex := (Flags => Disposition_Delete_Flags);
            Disposition : aliased Disposition_Info := (Delete_File => 1);
            Error : C_DWord := 0;
         begin
            --  The extended form needs Windows 10 1809 and NTFS; elsewhere
            --  the plain one still deletes what is not read-only.
            Ok := Set_File_Information
              (Held, File_Disposition_Info_Ex, Disposition_Ex'Address,
               C_DWord (Disposition_Info_Ex'Size / 8)) /= 0
              or else Set_File_Information
                (Held, File_Disposition_Info, Disposition'Address,
                 C_DWord (Disposition_Info'Size / 8)) /= 0;
            if not Ok then
               --  Why the plain form refused: a folder not empty, a file
               --  held open without delete sharing, a refused right.
               Error := Get_Last_Error;
               --  A read-only entry on a volume without the extended form
               --  (FAT, exFAT) goes once the attribute is dropped. If it
               --  still will not go, the attribute is put back: an entry
               --  that stays is left as it was found.
               if Drop_Read_Only (Held, Info) then
                  Ok := Set_File_Information
                    (Held, File_Disposition_Info, Disposition'Address,
                     C_DWord (Disposition_Info'Size / 8)) /= 0;
                  if not Ok then
                     Error := Get_Last_Error;
                     declare
                        --  Best effort: the deletion's error is the one reported.
                        Restored : constant Boolean := Set_Attributes (Held, Info.Attributes);
                        pragma Unreferenced (Restored);
                     begin
                        null;
                     end;
                  end if;
               end if;
               if not Ok then
                  Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Error));
               end if;
            end if;
         end;
      end if;
      Ignored := Close_Handle (Held);
      return Ok;
   exception
      when others =>
         Ignored := Close_Handle (Held);
         return False;
   end Delete_Held;

   Name : aliased Wide_String := Wide (Path);
   Held : System.Address;
begin
   if Path = "" then
      return Tree_Delete_Failed;
   end if;
   Held := Open_For_Delete (Name'Address);
   if Held = Invalid_Handle_Value then
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return Tree_Delete_Failed;
   end if;
   return (if Delete_Held (Held, 0) then Tree_Deleted else Tree_Delete_Failed);
exception
   when others =>
      return Tree_Delete_Failed;
end Delete_Tree_No_Follow;
