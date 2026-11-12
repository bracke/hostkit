with Ada.Characters.Handling;
with Ada.Numerics.Discrete_Random;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;

with Hostkit.Directory_Listing;
with Hostkit.Fs;
with Hostkit.Trash.Recycle_Bin_Format;
with Hostkit.Win32;
with Hostkit.Windows_Paths;
with Interfaces.C;
with System;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;

--  The Recycle Bin.
--
--  An item goes in through the shell's IFileOperation, the documented way to
--  recycle, which reports the item it made in the bin (PostDeleteItem's
--  psiNewlyCreated) -- so a caller learns where the item went and can restore
--  it later, which SHFileOperationW, used here before, never said. The shell
--  takes no path past 259 characters and no \\?\ form, so a longer path is
--  renamed into the bin folder directly and its $I file written as the shell
--  writes one (Hostkit.Trash.Recycle_Bin_Format); Explorer lists and restores
--  it like any other. Listing, restoring and purging read and move the same
--  files, as Explorer does.
package body Hostkit.Trash is
   use Ada.Strings.Unbounded;
   use Hostkit.Win32;
   use type Hostkit.Directory_Listing.Entry_Kind;
   use type Hostkit.Fs.Entry_Kind;
   use type Hostkit.Fs.Move_Outcome;
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;
   use type System.Address;

   package Format renames Hostkit.Trash.Recycle_Bin_Format;

   subtype C_DWord is Interfaces.C.unsigned_long;

   NUL : constant Wide_Character := Wide_Character'Val (0);

   --  The longest path the shell parses into an item.
   Shell_Limit : constant := 259;

   ----------------------------------------------------------------------
   --  Text
   ----------------------------------------------------------------------

   function UTF_16 (Value : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Value) & NUL);

   function UTF_8 (Units : Wide_String) return String is
     (Hostkit.Windows_Paths.To_UTF_8 (Units));

   --  Units up to the first NUL.
   function Until_NUL (Units : Wide_String) return Wide_String is
   begin
      for Index in Units'Range loop
         if Units (Index) = NUL then
            return Units (Units'First .. Index - 1);
         end if;
      end loop;
      return Units;
   end Until_NUL;

   --  A NUL-terminated UTF-16 string the host allocated.
   type Unit_Array is array (Positive range 1 .. 32_768) of Wide_Character
     with Convention => C;
   package Unit_Arrays is new System.Address_To_Access_Conversions (Unit_Array);

   function From_Host (Text : System.Address) return String is
   begin
      if Text = System.Null_Address then
         return "";
      end if;
      declare
         Units : constant Unit_Arrays.Object_Pointer := Unit_Arrays.To_Pointer (Text);
         Last  : Natural := 0;
      begin
         while Last < Unit_Array'Last and then Units (Last + 1) /= NUL loop
            Last := Last + 1;
         end loop;
         return UTF_8 (Wide_String (Units (1 .. Last)));
      end;
   end From_Host;

   --  Path with '\' separators, as the shell and a $I file write it.
   function Normalized (Path : String) return String is
      Result : String := Format.Without_Long_Prefix (Path);
   begin
      for Item of Result loop
         if Item = '/' then
            Item := '\';
         end if;
      end loop;
      return Result;
   end Normalized;

   function Last_Separator (Path : String) return Natural is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '\' then
            return Index;
         end if;
      end loop;
      return 0;
   end Last_Separator;

   function Leaf_Of (Path : String) return String is
      Separator : constant Natural := Last_Separator (Path);
   begin
      return (if Separator = 0 then Path else Path (Separator + 1 .. Path'Last));
   end Leaf_Of;

   --  The folder holding Path; a drive's root keeps its backslash (C:\).
   function Parent_Of (Path : String) return String is
      Separator : constant Natural := Last_Separator (Path);
   begin
      if Separator = 0 then
         return "";
      elsif Separator > Path'First and then Path (Separator - 1) = ':' then
         return Path (Path'First .. Separator);
      end if;
      return Path (Path'First .. Separator - 1);
   end Parent_Of;

   function Join (Folder : String; Name : String) return String is
     (if Folder'Length > 0 and then Folder (Folder'Last) = '\' then Folder & Name else Folder & "\" & Name);

   --  Equal but for the case of ASCII letters, as NTFS compares the names
   --  this looks at. Only ASCII is folded: To_Upper on Latin-1 would change
   --  the lead bytes of UTF-8 sequences.
   function Same_Text (Left, Right : String) return Boolean is
      function Folded (Item : Character) return Character is
        (if Item in 'a' .. 'z' then Ada.Characters.Handling.To_Upper (Item) else Item);
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;
      for Offset in 0 .. Left'Length - 1 loop
         if Folded (Left (Left'First + Offset)) /= Folded (Right (Right'First + Offset)) then
            return False;
         end if;
      end loop;
      return True;
   end Same_Text;

   ----------------------------------------------------------------------
   --  The host: volumes, the user's SID, the shell's change notices
   ----------------------------------------------------------------------

   function Get_Logical_Drives return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLogicalDrives";

   function Get_Windows_Directory_W (Buffer : System.Address; Size : Interfaces.C.unsigned) return Interfaces.C.unsigned
     with Import, Convention => Stdcall, External_Name => "GetWindowsDirectoryW";

   Drive_Fixed : constant Interfaces.C.unsigned := 3;

   --  SHQUERYRBINFO: 8-byte packing on 64-bit Windows.
   type Recycle_Bin_Info is record
      Size_Of    : Interfaces.Unsigned_32 := 0;
      Byte_Count : Interfaces.Integer_64 := 0;
      Item_Count : Interfaces.Integer_64 := 0;
   end record
     with Convention => C;

   function SH_Query_Recycle_Bin_W
     (Root : System.Address;
      Info : access Recycle_Bin_Info)
      return Interfaces.C.long
     with Import, Convention => Stdcall, External_Name => "SHQueryRecycleBinW";

   function Convert_Sid_To_String_Sid_W (Sid : System.Address; Text : access System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "ConvertSidToStringSidW";

   procedure SH_Change_Notify
     (Event  : Interfaces.C.long;
      Flags  : Interfaces.C.unsigned;
      Item_1 : System.Address;
      Item_2 : System.Address)
     with Import, Convention => Stdcall, External_Name => "SHChangeNotify";

   Token_User_Class : constant Interfaces.C.int := 1;
   Shcne_Update_Dir : constant Interfaces.C.long := 16#0000_1000#;
   Shcnf_Path_W     : constant Interfaces.C.unsigned := 16#0005#;

   --  The SID read once: a process's user does not change, and the trash
   --  view asks for its folder often.
   protected Sid_Cache is
      function Value return String;
      procedure Remember (Sid : String);
   private
      Cached : Unbounded_String;
   end Sid_Cache;

   protected body Sid_Cache is
      function Value return String is (To_String (Cached));

      procedure Remember (Sid : String) is
      begin
         Cached := To_Unbounded_String (Sid);
      end Remember;
   end Sid_Cache;

   --  The current user's SID as text (S-1-5-21-...), which names their
   --  folder in each $Recycle.Bin; "" when the token cannot be read.
   function Read_User_Sid return String is
      type Address_Array is array (1 .. 64) of System.Address
        with Convention => C;

      Token  : aliased System.Address := System.Null_Address;
      --  TOKEN_USER, then the SID it points at; addresses, so it is aligned.
      Room   : aliased Address_Array := [others => System.Null_Address];
      Needed : aliased C_DWord := 0;
      Text   : aliased System.Address := System.Null_Address;
      Read   : Interfaces.C.int;
      Ignored_Closed : Interfaces.C.int;
      Ignored_Freed  : System.Address;
   begin
      if Open_Process_Token (Get_Current_Process, Token_Query, Token'Access) = 0 then
         return "";
      end if;
      Read := Get_Token_Information (Token, Token_User_Class, Room'Address, Room'Size / 8, Needed'Access);
      Ignored_Closed := Close_Handle (Token);
      --  TOKEN_USER begins with SID_AND_ATTRIBUTES, whose first field is the SID.
      if Read = 0 or else Convert_Sid_To_String_Sid_W (Room (1), Text'Access) = 0 then
         return "";
      end if;
      declare
         Result : constant String := From_Host (Text);
      begin
         Ignored_Freed := Local_Free (Text);
         return Result;
      end;
   exception
      when others =>
         return "";
   end Read_User_Sid;

   function User_Sid return String is
      Known : constant String := Sid_Cache.Value;
   begin
      if Known /= "" then
         return Known;
      end if;
      declare
         Sid : constant String := Read_User_Sid;
      begin
         if Sid /= "" then
            Sid_Cache.Remember (Sid);
         end if;
         return Sid;
      end;
   end User_Sid;

   --  The root of Path's volume (C:\, \\server\share\, \\?\Volume{...}\),
   --  or "" when the host does not say.
   function Volume_Root (Path : String) return String is
      Wide_Path : aliased constant Wide_String := Hostkit.Windows_Paths.Native (Path);
      Root      : aliased Wide_String (1 .. 32_768) := [others => NUL];
   begin
      if Path = "" or else Get_Volume_Path_Name (Wide_Path'Address, Root'Address, Root'Length) = 0 then
         return "";
      end if;
      return Format.Without_Long_Prefix (UTF_8 (Until_NUL (Root)));
   exception
      when others =>
         return "";
   end Volume_Root;

   function Is_Fixed (Root : String) return Boolean is
      Wide_Root : aliased constant Wide_String := UTF_16 (Root);
   begin
      return Root /= "" and then Get_Drive_Type (Wide_Root'Address) = Drive_Fixed;
   end Is_Fixed;

   function Bin_Folder_On (Root : String; Sid : String) return String is
     (Join (Join (Root, "$Recycle.Bin"), Sid));

   function Is_Folder (Path : String) return Boolean is
     (not Hostkit.Fs.Is_Link (Path) and then Hostkit.Fs.Kind_Of (Path) = Hostkit.Fs.Directory_Entry);

   function Is_There (Path : String) return Boolean is
     (Hostkit.Fs.Is_Link (Path) or else Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Missing_Entry);

   --  Tell Explorer a folder changed, so an open Recycle Bin window shows
   --  what was put in or taken out. The shell takes no longer path.
   procedure Notify_Changed (Folder : String) is
      Wide_Folder : aliased constant Wide_String := UTF_16 (Folder);
   begin
      if Folder /= "" and then Wide_Folder'Length <= Shell_Limit + 1 then
         SH_Change_Notify (Shcne_Update_Dir, Shcnf_Path_W, Wide_Folder'Address, System.Null_Address);
      end if;
   exception
      when others =>
         null;
   end Notify_Changed;

   --  A file's bytes, at most Limit of them; empty when it cannot be read.
   function Read_Bytes (Path : String; Limit : Ada.Streams.Stream_Element_Offset)
     return Ada.Streams.Stream_Element_Array
   is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Hostkit.Fs.Open_Stream (File, Ada.Streams.Stream_IO.In_File, Path);
      declare
         Stored : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (Ada.Streams.Stream_IO.Size (File));
         Size   : constant Ada.Streams.Stream_Element_Offset := Ada.Streams.Stream_Element_Offset'Min (Limit, Stored);
         Data   : Ada.Streams.Stream_Element_Array (1 .. Size);
         Last   : Ada.Streams.Stream_Element_Offset;
      begin
         Ada.Streams.Stream_IO.Read (File, Data, Last);
         Ada.Streams.Stream_IO.Close (File);
         return Data (1 .. Last);
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return Ada.Streams.Stream_Element_Array'(1 .. 0 => 0);
   end Read_Bytes;

   --  The longest $I file: a version 2 header and a 32768-unit path.
   Longest_Info : constant := 28 + 2 * 32_768;

   ----------------------------------------------------------------------
   --  Facility
   ----------------------------------------------------------------------

   function Current return Facility is
   begin
      return
        (Available             => True,
         Api_Name              => To_Unbounded_String ("IFileOperation"),
         Uses_Recycle_Bin      => True,
         Preserves_Metadata    => True,
         Requires_User_Consent => False);
   end Current;

   function Can_Hold (Path : String) return Boolean is
      use type Interfaces.C.long;
      Info : aliased Recycle_Bin_Info;
   begin
      --  A share named by its UNC path (\\server\share) has no bin.
      if Path'Length >= 2 and then Path (Path'First) in '\' | '/' and then Path (Path'First + 1) in '\' | '/'
        and then Format.Without_Long_Prefix (Path) = Path
      then
         return False;
      end if;
      declare
         --  Asked through the long form, so a path past MAX_PATH is answered
         --  for its volume rather than refused as if it had none.
         Root      : constant String := Volume_Root (Path);
         Wide_Root : aliased constant Wide_String := UTF_16 (Root);
      begin
         if Root = ""
           or else (Root'Length >= 2 and then Root (Root'First .. Root'First + 1) = "\\"
                    and then not (Root'Length >= 4 and then Root (Root'First .. Root'First + 3) = "\\?\"))
           or else not Is_Fixed (Root)
         then
            return False;
         end if;
         Info.Size_Of := Interfaces.Unsigned_32 (Recycle_Bin_Info'Size / 8);
         return SH_Query_Recycle_Bin_W (Wide_Root'Address, Info'Access) = 0;
      end;
   exception
      when others =>
         return False;
   end Can_Hold;

   ----------------------------------------------------------------------
   --  Where the bins are and what they hold
   ----------------------------------------------------------------------

   function Recycle_Bin_Folder (Path : String) return String is
      Sid  : constant String := User_Sid;
      Root : constant String := (if Sid = "" then "" else Volume_Root (Path));
   begin
      if Root = "" then
         return "";
      end if;
      declare
         Folder : constant String := Bin_Folder_On (Root, Sid);
      begin
         return (if Is_Folder (Folder) then Folder else "");
      end;
   exception
      when others =>
         return "";
   end Recycle_Bin_Folder;

   function Recycle_Bin_Folders return String_Vectors.Vector is
      Result : String_Vectors.Vector;
      Sid    : constant String := User_Sid;
      Drives : constant C_DWord := Get_Logical_Drives;
   begin
      if Sid = "" then
         return Result;
      end if;
      for Letter in Character range 'A' .. 'Z' loop
         if (Drives and C_DWord'(2) ** (Character'Pos (Letter) - Character'Pos ('A'))) /= 0 then
            declare
               Root   : constant String := Letter & ":\";
               Folder : constant String := Bin_Folder_On (Root, Sid);
            begin
               if Is_Fixed (Root) and then Is_Folder (Folder) then
                  Result.Append (To_Unbounded_String (Folder));
               end if;
            end;
         end if;
      end loop;
      return Result;
   exception
      when others =>
         return Result;
   end Recycle_Bin_Folders;

   function Primary_Recycle_Bin_Folder return String is
      Windows : aliased Wide_String (1 .. 1_024) := [others => NUL];
      Length  : constant Interfaces.C.unsigned := Get_Windows_Directory_W (Windows'Address, Windows'Length);
   begin
      if Length >= 3 and then Length < Windows'Length then
         declare
            Directory : constant String := UTF_8 (Windows (1 .. Natural (Length)));
            Folder    : constant String :=
              (if Directory'Length >= 3 and then Directory (Directory'First + 1) = ':'
               then Recycle_Bin_Folder (Directory (Directory'First .. Directory'First + 2))
               else "");
         begin
            if Folder /= "" then
               return Folder;
            end if;
         end;
      end if;
      declare
         Folders : constant String_Vectors.Vector := Recycle_Bin_Folders;
      begin
         return (if Folders.Is_Empty then "" else To_String (Folders.First_Element));
      end;
   exception
      when others =>
         return "";
   end Primary_Recycle_Bin_Folder;

   function Is_Recycled_Item (Path : String) return Boolean is
      Item   : constant String := Normalized (Path);
      Folder : constant String := Parent_Of (Item);
      Bin    : constant String := Parent_Of (Folder);
   begin
      if not Format.Is_Recycled_Name (Leaf_Of (Item)) or else Folder = "" or else Bin = "" then
         return False;
      end if;
      declare
         Sid : constant String := User_Sid;
      begin
         return Sid /= "" and then Same_Text (Leaf_Of (Folder), Sid) and then Same_Text (Leaf_Of (Bin), "$Recycle.Bin");
      end;
   exception
      when others =>
         return False;
   end Is_Recycled_Item;

   --  Info_Path's record as an entry for Recycled_Path.
   function Read_Entry (Recycled_Path, Info_Path : String; Item : out Recycle_Bin_Entry) return Boolean is
      Info : Format.Info_Record;
   begin
      Item := (others => <>);
      if not Format.Decode (Read_Bytes (Info_Path, Longest_Info), Info) then
         return False;
      end if;
      Item.Recycled_Path := To_Unbounded_String (Recycled_Path);
      Item.Info_Path := To_Unbounded_String (Info_Path);
      Item.Original_Path := Info.Original_Path;
      Item.Size := Info.Size;
      Item.Deleted_Known := Format.To_Time (Info.Deleted, Item.Deleted);
      return True;
   end Read_Entry;

   function Entry_Of (Recycled_Path : String; Item : out Recycle_Bin_Entry) return Boolean is
      Path : constant String := Normalized (Recycled_Path);
   begin
      Item := (others => <>);
      if not Is_Recycled_Item (Path) then
         return False;
      end if;
      return Read_Entry (Path, Join (Parent_Of (Path), Format.Info_Name_Of (Leaf_Of (Path))), Item);
   exception
      when others =>
         Item := (others => <>);
         return False;
   end Entry_Of;

   --  Every entry in one bin folder whose $R item is still there.
   procedure Add_Entries (Folder : String; Into : in out Recycle_Bin_Entry_Vectors.Vector) is
      Listed : Hostkit.Directory_Listing.Entry_Vectors.Vector;
   begin
      if not Hostkit.Directory_Listing.List (Folder, Listed) then
         return;
      end if;
      for Found of Listed loop
         declare
            Recycled_Name : constant String := Format.Recycled_Name_Of (Found.Name);
            Item          : Recycle_Bin_Entry;
         begin
            if Found.Kind = Hostkit.Directory_Listing.Regular_File
              and then Recycled_Name /= ""
              and then Is_There (Join (Folder, Recycled_Name))
              and then Read_Entry (Join (Folder, Recycled_Name), Join (Folder, Found.Name), Item)
            then
               Into.Append (Item);
            end if;
         end;
      end loop;
   end Add_Entries;

   function Recycle_Bin_Entries (Volume : String := "") return Recycle_Bin_Entry_Vectors.Vector is
      Result : Recycle_Bin_Entry_Vectors.Vector;
   begin
      if Volume /= "" then
         declare
            Folder : constant String := Recycle_Bin_Folder (Volume);
         begin
            if Folder /= "" then
               Add_Entries (Folder, Result);
            end if;
         end;
      else
         for Folder of Recycle_Bin_Folders loop
            Add_Entries (To_String (Folder), Result);
         end loop;
      end if;
      return Result;
   exception
      when others =>
         return Result;
   end Recycle_Bin_Entries;

   --  The newest item in Path's bin recorded as having come from Path: where
   --  the shell put it, when it did not say.
   function Find_Recycled (Path : String) return String is
      Entries : Recycle_Bin_Entry_Vectors.Vector;
      Best    : Unbounded_String;
      Newest  : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Found   : Boolean := False;
   begin
      Entries := Recycle_Bin_Entries (Path);
      for Item of Entries loop
         if Same_Text (To_String (Item.Original_Path), Path) then
            declare
               use type Ada.Calendar.Time;
            begin
               if not Found or else (Item.Deleted_Known and then Item.Deleted > Newest) then
                  Best := Item.Recycled_Path;
                  Newest := Item.Deleted;
                  Found := True;
               end if;
            end;
         end if;
      end loop;
      return To_String (Best);
   end Find_Recycled;

   ----------------------------------------------------------------------
   --  COM: IFileOperation and a progress sink of our own
   ----------------------------------------------------------------------

   type HRESULT is new Interfaces.Unsigned_32;

   S_OK               : constant HRESULT := 0;
   S_False            : constant HRESULT := 1;
   E_No_Interface     : constant HRESULT := 16#8000_4002#;
   E_Pointer          : constant HRESULT := 16#8000_4003#;
   E_Abort            : constant HRESULT := 16#8000_4004#;
   E_Fail             : constant HRESULT := 16#8000_4005#;

   function Failed (Result : HRESULT) return Boolean is ((Result and 16#8000_0000#) /= 0);

   type GUID_Tail is array (1 .. 8) of Interfaces.Unsigned_8
     with Convention => C;

   type GUID is record
      Data_1 : Interfaces.Unsigned_32;
      Data_2 : Interfaces.Unsigned_16;
      Data_3 : Interfaces.Unsigned_16;
      Data_4 : GUID_Tail;
   end record
     with Convention => C;

   --  {3AD05575-8857-4850-9277-11B85BDB8E09}
   CLSID_File_Operation : aliased constant GUID :=
     (16#3AD0_5575#, 16#8857#, 16#4850#, [16#92#, 16#77#, 16#11#, 16#B8#, 16#5B#, 16#DB#, 16#8E#, 16#09#]);

   --  {947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8}
   IID_File_Operation : aliased constant GUID :=
     (16#947A_AB5F#, 16#0A5C#, 16#4C13#, [16#B4#, 16#D6#, 16#4B#, 16#F7#, 16#83#, 16#6F#, 16#C9#, 16#F8#]);

   --  {43826D1E-E718-42EE-BC55-A1E261C37BFE}
   IID_Shell_Item : aliased constant GUID :=
     (16#4382_6D1E#, 16#E718#, 16#42EE#, [16#BC#, 16#55#, 16#A1#, 16#E2#, 16#61#, 16#C3#, 16#7B#, 16#FE#]);

   --  {00000000-0000-0000-C000-000000000046}
   IID_Unknown : constant GUID :=
     (0, 0, 0, [16#C0#, 0, 0, 0, 0, 0, 0, 16#46#]);

   --  {04B0F1A7-9490-44BC-96E1-4296A31252E2}
   IID_Progress_Sink : constant GUID :=
     (16#04B0_F1A7#, 16#9490#, 16#44BC#, [16#96#, 16#E1#, 16#42#, 16#96#, 16#A3#, 16#12#, 16#52#, 16#E2#]);

   function Co_Initialize_Ex (Reserved : System.Address; Model : C_DWord) return HRESULT
     with Import, Convention => Stdcall, External_Name => "CoInitializeEx";

   procedure Co_Uninitialize
     with Import, Convention => Stdcall, External_Name => "CoUninitialize";

   function Co_Create_Instance
     (Class   : access constant GUID;
      Outer   : System.Address;
      Context : C_DWord;
      Iid     : access constant GUID;
      Object  : access System.Address)
      return HRESULT
     with Import, Convention => Stdcall, External_Name => "CoCreateInstance";

   procedure Co_Task_Mem_Free (Memory : System.Address)
     with Import, Convention => Stdcall, External_Name => "CoTaskMemFree";

   function SH_Create_Item_From_Parsing_Name
     (Path         : System.Address;
      Bind_Context : System.Address;
      Iid          : access constant GUID;
      Item         : access System.Address)
      return HRESULT
     with Import, Convention => Stdcall, External_Name => "SHCreateItemFromParsingName";

   Coinit_Apartment_Threaded : constant C_DWord := 16#2#;
   Coinit_Disable_Ole1dde    : constant C_DWord := 16#4#;
   Clsctx_All                : constant C_DWord := 16#17#;

   --  FOF_NO_UI (silent, no confirmation, no error UI, no confirm-mkdir),
   --  FOF_ALLOWUNDO and FOFX_RECYCLEONDELETE: recycle, and draw nothing.
   --  FOFX_EARLYFAILURE: stop at the first failure rather than go on.
   Operation_Flags : constant C_DWord := 16#0614# or 16#0040# or 16#0008_0000# or 16#0010_0000#;

   --  TSF_DELETE_RECYCLE_IF_POSSIBLE, in PreDeleteItem's flags: the shell is
   --  about to recycle the item. Without it, it is about to destroy it.
   Tsf_Delete_Recycle_If_Possible : constant C_DWord := 16#0080#;

   --  SIGDN_FILESYSPATH.
   Sigdn_File_Sys_Path : constant Interfaces.Unsigned_32 := 16#8005_8000#;

   --  A vtable slot of a COM object: its first word points at the table.
   package Address_Cells is new System.Address_To_Access_Conversions (System.Address);

   function Slot (Object : System.Address; Index : Natural) return System.Address is
      Table : constant System.Address := Address_Cells.To_Pointer (Object).all;
   begin
      return Address_Cells.To_Pointer
        (System.Storage_Elements."+"
           (Table, System.Storage_Elements.Storage_Offset (Index * (System.Address'Size / 8)))).all;
   end Slot;

   --  The methods called, by signature. IUnknown is 0 .. 2 on every interface.
   type Release_Method is access function (This : System.Address) return Interfaces.Unsigned_32
     with Convention => Stdcall;
   type Flags_Method is access function (This : System.Address; Flags : C_DWord) return HRESULT
     with Convention => Stdcall;
   type Delete_Item_Method is access function (This, Item, Sink : System.Address) return HRESULT
     with Convention => Stdcall;
   type Perform_Method is access function (This : System.Address) return HRESULT
     with Convention => Stdcall;
   type Any_Aborted_Method is access function (This : System.Address; Aborted : access Interfaces.C.int) return HRESULT
     with Convention => Stdcall;
   type Display_Name_Method is access function
     (This : System.Address; Kind : Interfaces.Unsigned_32; Name : access System.Address) return HRESULT
     with Convention => Stdcall;

   function To_Release is new Ada.Unchecked_Conversion (System.Address, Release_Method);
   function To_Flags is new Ada.Unchecked_Conversion (System.Address, Flags_Method);
   function To_Delete_Item is new Ada.Unchecked_Conversion (System.Address, Delete_Item_Method);
   function To_Perform is new Ada.Unchecked_Conversion (System.Address, Perform_Method);
   function To_Any_Aborted is new Ada.Unchecked_Conversion (System.Address, Any_Aborted_Method);
   function To_Display_Name is new Ada.Unchecked_Conversion (System.Address, Display_Name_Method);

   --  IUnknown::Release = 2; IFileOperation: SetOperationFlags = 5,
   --  DeleteItem = 18, PerformOperations = 21, GetAnyOperationsAborted = 22;
   --  IShellItem::GetDisplayName = 5.
   Release_Slot           : constant := 2;
   Set_Flags_Slot         : constant := 5;
   Delete_Item_Slot       : constant := 18;
   Perform_Slot           : constant := 21;
   Any_Aborted_Slot       : constant := 22;
   Get_Display_Name_Slot  : constant := 5;

   procedure Release (Object : in out System.Address) is
      Ignored_Count : Interfaces.Unsigned_32;
   begin
      if Object /= System.Null_Address then
         Ignored_Count := To_Release (Slot (Object, Release_Slot)) (Object);
         Object := System.Null_Address;
      end if;
   end Release;

   --  An IShellItem's file-system path, or "".
   function File_System_Path (Item : System.Address) return String is
      Name : aliased System.Address := System.Null_Address;
   begin
      if Item = System.Null_Address
        or else Failed (To_Display_Name (Slot (Item, Get_Display_Name_Slot)) (Item, Sigdn_File_Sys_Path, Name'Access))
      then
         return "";
      end if;
      declare
         Result : constant String := From_Host (Name);
      begin
         Co_Task_Mem_Free (Name);
         return Result;
      end;
   exception
      when others =>
         return "";
   end File_System_Path;

   --  What the sink learns. The COM object is the two words Sink_Object
   --  holds: the vtable, as COM requires first, and this state.
   type Sink_State is record
      References    : Interfaces.Unsigned_32 := 1;
      Recycled      : Unbounded_String;
      Would_Destroy : Boolean := False;
   end record;

   type Sink_Object is record
      Table : System.Address := System.Null_Address;
      State : System.Address := System.Null_Address;
   end record
     with Convention => C;

   package Sink_Objects is new System.Address_To_Access_Conversions (Sink_Object);
   package Sink_States is new System.Address_To_Access_Conversions (Sink_State);

   function State_Of (This : System.Address) return Sink_States.Object_Pointer is
     (Sink_States.To_Pointer (Sink_Objects.To_Pointer (This).State));

   --  IFileOperationProgressSink, every method in vtable order. Nothing may
   --  propagate into the shell, so each one that can raise answers E_FAIL.

   function Sink_Query_Interface
     (This   : System.Address;
      Iid    : access constant GUID;
      Object : access System.Address)
      return HRESULT
     with Convention => Stdcall;

   function Sink_Add_Ref (This : System.Address) return Interfaces.Unsigned_32
     with Convention => Stdcall;

   function Sink_Release (This : System.Address) return Interfaces.Unsigned_32
     with Convention => Stdcall;

   --  StartOperations, ResetTimer, PauseTimer and ResumeTimer.
   function Sink_Nothing (This : System.Address) return HRESULT
     with Convention => Stdcall;

   function Sink_Finish_Operations (This : System.Address; Result : HRESULT) return HRESULT
     with Convention => Stdcall;

   function Sink_Pre_Rename_Item
     (This : System.Address; Flags : C_DWord; Item, New_Name : System.Address) return HRESULT
     with Convention => Stdcall;

   function Sink_Post_Rename_Item
     (This          : System.Address;
      Flags         : C_DWord;
      Item          : System.Address;
      New_Name      : System.Address;
      Rename_Result : HRESULT;
      Newly_Created : System.Address)
      return HRESULT
     with Convention => Stdcall;

   --  PreMoveItem and PreCopyItem.
   function Sink_Pre_Transfer_Item
     (This : System.Address; Flags : C_DWord; Item, Destination, New_Name : System.Address) return HRESULT
     with Convention => Stdcall;

   --  PostMoveItem and PostCopyItem.
   function Sink_Post_Transfer_Item
     (This            : System.Address;
      Flags           : C_DWord;
      Item            : System.Address;
      Destination     : System.Address;
      New_Name        : System.Address;
      Transfer_Result : HRESULT;
      Newly_Created   : System.Address)
      return HRESULT
     with Convention => Stdcall;

   function Sink_Pre_Delete_Item (This : System.Address; Flags : C_DWord; Item : System.Address) return HRESULT
     with Convention => Stdcall;

   function Sink_Post_Delete_Item
     (This          : System.Address;
      Flags         : C_DWord;
      Item          : System.Address;
      Delete_Result : HRESULT;
      Newly_Created : System.Address)
      return HRESULT
     with Convention => Stdcall;

   function Sink_Pre_New_Item
     (This : System.Address; Flags : C_DWord; Destination, New_Name : System.Address) return HRESULT
     with Convention => Stdcall;

   function Sink_Post_New_Item
     (This          : System.Address;
      Flags         : C_DWord;
      Destination   : System.Address;
      New_Name      : System.Address;
      Template_Name : System.Address;
      Attributes    : C_DWord;
      New_Result    : HRESULT;
      Newly_Created : System.Address)
      return HRESULT
     with Convention => Stdcall;

   function Sink_Update_Progress
     (This : System.Address; Work_Total, Work_So_Far : Interfaces.C.unsigned) return HRESULT
     with Convention => Stdcall;

   function Sink_Query_Interface
     (This   : System.Address;
      Iid    : access constant GUID;
      Object : access System.Address)
      return HRESULT
   is
      Ignored_Count : Interfaces.Unsigned_32;
   begin
      if Object = null then
         return E_Pointer;
      elsif Iid /= null and then (Iid.all = IID_Unknown or else Iid.all = IID_Progress_Sink) then
         Object.all := This;
         Ignored_Count := Sink_Add_Ref (This);
         return S_OK;
      end if;
      Object.all := System.Null_Address;
      return E_No_Interface;
   exception
      when others =>
         return E_Fail;
   end Sink_Query_Interface;

   --  The sink lives on the stack of the call that made it and outlives the
   --  operation it is given to, so the count is kept honest but frees nothing.
   function Sink_Add_Ref (This : System.Address) return Interfaces.Unsigned_32 is
      State : constant Sink_States.Object_Pointer := State_Of (This);
   begin
      State.References := State.References + 1;
      return State.References;
   exception
      when others =>
         return 1;
   end Sink_Add_Ref;

   function Sink_Release (This : System.Address) return Interfaces.Unsigned_32 is
      State : constant Sink_States.Object_Pointer := State_Of (This);
   begin
      if State.References > 1 then
         State.References := State.References - 1;
      end if;
      return State.References;
   exception
      when others =>
         return 1;
   end Sink_Release;

   function Sink_Nothing (This : System.Address) return HRESULT is
      pragma Unreferenced (This);
   begin
      return S_OK;
   end Sink_Nothing;

   function Sink_Finish_Operations (This : System.Address; Result : HRESULT) return HRESULT is
      pragma Unreferenced (This, Result);
   begin
      return S_OK;
   end Sink_Finish_Operations;

   function Sink_Pre_Rename_Item
     (This : System.Address; Flags : C_DWord; Item, New_Name : System.Address) return HRESULT
   is
      pragma Unreferenced (This, Flags, Item, New_Name);
   begin
      return S_OK;
   end Sink_Pre_Rename_Item;

   function Sink_Post_Rename_Item
     (This          : System.Address;
      Flags         : C_DWord;
      Item          : System.Address;
      New_Name      : System.Address;
      Rename_Result : HRESULT;
      Newly_Created : System.Address)
      return HRESULT
   is
      pragma Unreferenced (This, Flags, Item, New_Name, Rename_Result, Newly_Created);
   begin
      return S_OK;
   end Sink_Post_Rename_Item;

   function Sink_Pre_Transfer_Item
     (This : System.Address; Flags : C_DWord; Item, Destination, New_Name : System.Address) return HRESULT
   is
      pragma Unreferenced (This, Flags, Item, Destination, New_Name);
   begin
      return S_OK;
   end Sink_Pre_Transfer_Item;

   function Sink_Post_Transfer_Item
     (This            : System.Address;
      Flags           : C_DWord;
      Item            : System.Address;
      Destination     : System.Address;
      New_Name        : System.Address;
      Transfer_Result : HRESULT;
      Newly_Created   : System.Address)
      return HRESULT
   is
      pragma Unreferenced (This, Flags, Item, Destination, New_Name, Transfer_Result, Newly_Created);
   begin
      return S_OK;
   end Sink_Post_Transfer_Item;

   --  The guard that makes this a trash and never a delete: asked to destroy
   --  rather than recycle (an item too big for the bin, a bin set to delete
   --  at once), the operation is aborted and the item stays where it was.
   function Sink_Pre_Delete_Item (This : System.Address; Flags : C_DWord; Item : System.Address) return HRESULT is
      pragma Unreferenced (Item);
   begin
      if (Flags and Tsf_Delete_Recycle_If_Possible) = 0 then
         State_Of (This).Would_Destroy := True;
         return E_Abort;
      end if;
      return S_OK;
   exception
      when others =>
         return E_Abort;
   end Sink_Pre_Delete_Item;

   --  Where the item went: the item the shell made in the bin.
   function Sink_Post_Delete_Item
     (This          : System.Address;
      Flags         : C_DWord;
      Item          : System.Address;
      Delete_Result : HRESULT;
      Newly_Created : System.Address)
      return HRESULT
   is
      pragma Unreferenced (Flags, Item);
   begin
      if not Failed (Delete_Result) and then Newly_Created /= System.Null_Address then
         State_Of (This).Recycled := To_Unbounded_String (File_System_Path (Newly_Created));
      end if;
      return S_OK;
   exception
      when others =>
         return S_OK;
   end Sink_Post_Delete_Item;

   function Sink_Pre_New_Item
     (This : System.Address; Flags : C_DWord; Destination, New_Name : System.Address) return HRESULT
   is
      pragma Unreferenced (This, Flags, Destination, New_Name);
   begin
      return S_OK;
   end Sink_Pre_New_Item;

   function Sink_Post_New_Item
     (This          : System.Address;
      Flags         : C_DWord;
      Destination   : System.Address;
      New_Name      : System.Address;
      Template_Name : System.Address;
      Attributes    : C_DWord;
      New_Result    : HRESULT;
      Newly_Created : System.Address)
      return HRESULT
   is
      pragma Unreferenced (This, Flags, Destination, New_Name, Template_Name, Attributes, New_Result, Newly_Created);
   begin
      return S_OK;
   end Sink_Post_New_Item;

   function Sink_Update_Progress
     (This : System.Address; Work_Total, Work_So_Far : Interfaces.C.unsigned) return HRESULT
   is
      pragma Unreferenced (This, Work_Total, Work_So_Far);
   begin
      return S_OK;
   end Sink_Update_Progress;

   type Method_Table is array (0 .. 18) of System.Address
     with Convention => C;

   --  IUnknown, then IFileOperationProgressSink in its declared order.
   Sink_Table : aliased constant Method_Table :=
     [0  => Sink_Query_Interface'Address,
      1  => Sink_Add_Ref'Address,
      2  => Sink_Release'Address,
      3  => Sink_Nothing'Address,             --  StartOperations
      4  => Sink_Finish_Operations'Address,   --  FinishOperations
      5  => Sink_Pre_Rename_Item'Address,     --  PreRenameItem
      6  => Sink_Post_Rename_Item'Address,    --  PostRenameItem
      7  => Sink_Pre_Transfer_Item'Address,   --  PreMoveItem
      8  => Sink_Post_Transfer_Item'Address,  --  PostMoveItem
      9  => Sink_Pre_Transfer_Item'Address,   --  PreCopyItem
      10 => Sink_Post_Transfer_Item'Address,  --  PostCopyItem
      11 => Sink_Pre_Delete_Item'Address,     --  PreDeleteItem
      12 => Sink_Post_Delete_Item'Address,    --  PostDeleteItem
      13 => Sink_Pre_New_Item'Address,        --  PreNewItem
      14 => Sink_Post_New_Item'Address,       --  PostNewItem
      15 => Sink_Update_Progress'Address,     --  UpdateProgress
      16 => Sink_Nothing'Address,             --  ResetTimer
      17 => Sink_Nothing'Address,             --  PauseTimer
      18 => Sink_Nothing'Address];            --  ResumeTimer

   type Shell_Result is
     (Shell_Recycled,
      --  The shell refused, or would have destroyed the item.
      Shell_Refused,
      --  COM is not ours to use on this thread (it is a multithreaded
      --  apartment, where the shell's objects call back through proxies a
      --  sink of ours does not have), or the shell object would not start.
      Shell_Unavailable);

   --  Recycle Path through IFileOperation on this thread, in a
   --  single-threaded apartment this call opens (and closes again) unless the
   --  thread is in one already.
   function Move_By_Shell
     (Wide_Path     : Wide_String;
      Recycled      : out Unbounded_String;
      Would_Destroy : out Boolean)
      return Shell_Result
   is
      Opened : constant HRESULT :=
        Co_Initialize_Ex (System.Null_Address, Coinit_Apartment_Threaded or Coinit_Disable_Ole1dde);
   begin
      Recycled := Null_Unbounded_String;
      Would_Destroy := False;
      --  S_FALSE: already a single-threaded apartment, and still ours to
      --  balance. RPC_E_CHANGED_MODE and anything else: not ours to use.
      if Opened /= S_OK and then Opened /= S_False then
         return Shell_Unavailable;
      end if;

      declare
         State     : aliased Sink_State;
         Sink      : aliased Sink_Object := (Table => Sink_Table'Address, State => State'Address);
         Operation : aliased System.Address := System.Null_Address;
         Item      : aliased System.Address := System.Null_Address;
         Shell_Path : aliased constant Wide_String := Wide_Path;
         Aborted   : aliased Interfaces.C.int := 0;
         Result    : Shell_Result := Shell_Refused;
      begin
         if Failed
              (Co_Create_Instance
                 (CLSID_File_Operation'Access, System.Null_Address, Clsctx_All, IID_File_Operation'Access,
                  Operation'Access))
         then
            Result := Shell_Unavailable;
         elsif not Failed (To_Flags (Slot (Operation, Set_Flags_Slot)) (Operation, Operation_Flags))
           and then not Failed
             (SH_Create_Item_From_Parsing_Name
                (Shell_Path'Address, System.Null_Address, IID_Shell_Item'Access, Item'Access))
           and then not Failed (To_Delete_Item (Slot (Operation, Delete_Item_Slot)) (Operation, Item, Sink'Address))
         then
            declare
               Performed : constant HRESULT := To_Perform (Slot (Operation, Perform_Slot)) (Operation);
            begin
               if not Failed (To_Any_Aborted (Slot (Operation, Any_Aborted_Slot)) (Operation, Aborted'Access))
                 and then not Failed (Performed)
                 and then Aborted = 0
                 and then not State.Would_Destroy
               then
                  Result := Shell_Recycled;
               end if;
            end;
         end if;
         Release (Item);
         Release (Operation);
         Recycled := State.Recycled;
         Would_Destroy := State.Would_Destroy;
         Co_Uninitialize;
         return Result;
      exception
         when others =>
            Release (Item);
            Release (Operation);
            Co_Uninitialize;
            return Shell_Refused;
      end;
   end Move_By_Shell;

   ----------------------------------------------------------------------
   --  The direct route, for a path the shell cannot take
   ----------------------------------------------------------------------

   subtype Suffix_Index is Positive range 1 .. 36;
   package Random_Suffixes is new Ada.Numerics.Discrete_Random (Suffix_Index);

   --  Six of what Explorer uses: capitals and digits.
   function Random_Suffix (Generator : Random_Suffixes.Generator) return String is
      Alphabet : constant String (Suffix_Index) := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
      Result   : String (1 .. 6);
   begin
      for Item of Result loop
         Item := Alphabet (Random_Suffixes.Random (Generator));
      end loop;
      return Result;
   end Random_Suffix;

   --  A folder's total size, as Explorer records it in the $I file. Links
   --  are not followed; a tree too big to walk is recorded as far as walked.
   function Tree_Size (Path : String; Budget : in out Natural) return Interfaces.Integer_64 is
      Listed : Hostkit.Directory_Listing.Entry_Vectors.Vector;
      Total  : Interfaces.Integer_64 := 0;
   begin
      if Budget = 0 or else not Hostkit.Directory_Listing.List (Path, Listed) then
         return 0;
      end if;
      for Found of Listed loop
         exit when Budget = 0;
         Budget := Budget - 1;
         declare
            Child : constant String := Join (Path, Found.Name);
         begin
            case Found.Kind is
               when Hostkit.Directory_Listing.Regular_File =>
                  Total := Total + Interfaces.Integer_64 (Hostkit.Fs.Size_Of (Child, Follow_Links => False));
               when Hostkit.Directory_Listing.Directory =>
                  Total := Total + Tree_Size (Child, Budget);
               when others =>
                  null;
            end case;
         exception
            when others =>
               --  One unreadable entry is not the folder's whole size.
               null;
         end;
      end loop;
      return Total;
   end Tree_Size;

   function Move_Directly
     (Path          : String;
      Recycled_Path : out UString;
      Info_Path     : out UString)
      return Recycle_Outcome
   is
      Sid       : constant String := User_Sid;
      Root      : constant String := (if Sid = "" then "" else Volume_Root (Path));
      Folder    : constant String := (if Root = "" then "" else Bin_Folder_On (Root, Sid));
      Listed    : Hostkit.Directory_Listing.Entry_Vectors.Vector;
      Generator : Random_Suffixes.Generator;
   begin
      Recycled_Path := Null_Unbounded_String;
      Info_Path := Null_Unbounded_String;
      if Folder = "" then
         return Recycle_Refused;
      elsif not Is_Folder (Folder) then
         --  The shell's to create, with the permissions it gives it.
         return Recycle_Bin_Missing;
      elsif not Hostkit.Directory_Listing.List (Folder, Listed) then
         return Recycle_Refused;
      end if;

      --  An $I file this does not know how to write beside.
      for Found of Listed loop
         if Found.Kind = Hostkit.Directory_Listing.Regular_File
           and then Format.Recycled_Name_Of (Found.Name) /= ""
           and then Format.Version_Of (Read_Bytes (Join (Folder, Found.Name), 8)) > Format.Newest_Version
         then
            return Recycle_Bin_Newer_Format;
         end if;
      end loop;

      Random_Suffixes.Reset (Generator);
      declare
         Directory : constant Boolean := Is_Folder (Path);
         Size      : Interfaces.Integer_64 := 0;
         Budget    : Natural := 200_000;
         Leaf      : constant String := Leaf_Of (Path);
         Suffix    : Unbounded_String;
      begin
         begin
            Size :=
              (if Directory then Tree_Size (Path, Budget)
               else Interfaces.Integer_64 (Hostkit.Fs.Size_Of (Path, Follow_Links => False)));
         exception
            when others =>
               Size := 0;
         end;

         for Attempt in 1 .. 64 loop
            declare
               Candidate : constant String := Random_Suffix (Generator);
               Name      : constant String := Format.Recycled_Name_For (Candidate, Leaf, Directory);
            begin
               if not Is_There (Join (Folder, Name))
                 and then not Is_There (Join (Folder, Format.Info_Name_Of (Name)))
                 and then not Is_There (Join (Folder, "$H" & Candidate & ".tmp"))
               then
                  Suffix := To_Unbounded_String (Candidate);
                  exit;
               end if;
            end;
         end loop;
         if Suffix = Null_Unbounded_String then
            return Recycle_Refused;
         end if;

         declare
            Name     : constant String := Format.Recycled_Name_For (To_String (Suffix), Leaf, Directory);
            Item     : constant String := Join (Folder, Name);
            Info     : constant String := Join (Folder, Format.Info_Name_Of (Name));
            --  The record is written beside the bin under a name the shell
            --  ignores, and renamed to its $I name only once the item is in:
            --  the bin never lists a record for an item that is not there.
            Staged   : constant String := Join (Folder, "$H" & To_String (Suffix) & ".tmp");
            Record_Bytes : constant Ada.Streams.Stream_Element_Array :=
              Format.Encode
                ((Version       => Format.Newest_Version,
                  Size          => Size,
                  Deleted       => Format.To_Filetime (Ada.Calendar.Clock),
                  Original_Path => To_Unbounded_String (Path)));
            File     : Ada.Streams.Stream_IO.File_Type;
            Ignored_Removed : Boolean;
         begin
            begin
               Hostkit.Fs.Create_Stream (File, Ada.Streams.Stream_IO.Out_File, Staged);
               Ada.Streams.Stream_IO.Write (File, Record_Bytes);
               Ada.Streams.Stream_IO.Close (File);
            exception
               when others =>
                  if Ada.Streams.Stream_IO.Is_Open (File) then
                     Ada.Streams.Stream_IO.Close (File);
                  end if;
                  Ignored_Removed := Hostkit.Fs.Delete_File (Staged);
                  return Recycle_Refused;
            end;

            --  Same volume, so a rename: the item is never copied, and never
            --  anywhere but here or there.
            if Hostkit.Fs.Move_No_Replace_Outcome (Path, Item) /= Hostkit.Fs.Moved then
               Ignored_Removed := Hostkit.Fs.Delete_File (Staged);
               return Recycle_Refused;
            end if;
            if not Hostkit.Fs.Move_No_Replace (Staged, Info) then
               --  Without its record the bin would not list it: put it back.
               Ignored_Removed := Hostkit.Fs.Move_No_Replace (Item, Path);
               Ignored_Removed := Hostkit.Fs.Delete_File (Staged);
               return Recycle_Refused;
            end if;

            Notify_Changed (Folder);
            Notify_Changed (Parent_Of (Path));
            Recycled_Path := To_Unbounded_String (Item);
            Info_Path := To_Unbounded_String (Info);
            return Recycled;
         end;
      end;
   exception
      when others =>
         return Recycle_Refused;
   end Move_Directly;

   ----------------------------------------------------------------------
   --  Moving in, back out, and away for good
   ----------------------------------------------------------------------

   function Move_To_Recycle_Bin
     (Path          : String;
      Recycled_Path : out UString;
      Info_Path     : out UString)
      return Recycle_Outcome
   is
      Full : constant String := Normalized (Path);
   begin
      Recycled_Path := Null_Unbounded_String;
      Info_Path := Null_Unbounded_String;
      --  The bin itself, or anything in it, would go into itself.
      if Full = "" or else Format.Inside_Recycle_Bin (Full) or else not Is_There (Full) then
         return Recycle_Refused;
      elsif not Can_Hold (Full) then
         return Recycle_Volume_Unavailable;
      end if;

      if Hostkit.Windows_Paths.From_UTF_8 (Full)'Length <= Shell_Limit then
         declare
            Reported      : Unbounded_String;
            Would_Destroy : Boolean;
         begin
            case Move_By_Shell (UTF_16 (Full), Reported, Would_Destroy) is
               when Shell_Recycled =>
                  declare
                     Where : constant String :=
                       (if Is_Recycled_Item (To_String (Reported)) then Normalized (To_String (Reported))
                        else Find_Recycled (Full));
                  begin
                     if Where /= "" then
                        Recycled_Path := To_Unbounded_String (Where);
                        Info_Path := To_Unbounded_String
                          (Join (Parent_Of (Where), Format.Info_Name_Of (Leaf_Of (Where))));
                     end if;
                     return Recycled;
                  end;
               when Shell_Refused =>
                  --  Refused outright: the item is in use, gone, or not ours.
                  --  Refused because the shell would have destroyed it: the
                  --  bin's folder can still take it by rename, which never
                  --  destroys anything.
                  if not Would_Destroy then
                     return Recycle_Refused;
                  end if;
               when Shell_Unavailable =>
                  null;
            end case;
         end;
      end if;

      return Move_Directly (Full, Recycled_Path, Info_Path);
   exception
      when others =>
         return Recycle_Refused;
   end Move_To_Recycle_Bin;

   function Move_To_Trash (Path : String) return Boolean is
      Ignored_Recycled, Ignored_Info : UString;
   begin
      return Move_To_Recycle_Bin (Path, Ignored_Recycled, Ignored_Info) = Recycled;
   end Move_To_Trash;

   function Restore (Recycled_Path : String; Destination : String := "") return Restore_Outcome is
      Item : Recycle_Bin_Entry;
   begin
      if not Entry_Of (Recycled_Path, Item) or else not Is_There (To_String (Item.Recycled_Path)) then
         return Restore_Not_In_Bin;
      end if;

      declare
         From   : constant String := To_String (Item.Recycled_Path);
         Target : constant String :=
           Normalized (if Destination = "" then To_String (Item.Original_Path) else Destination);
         Parent : constant String := Parent_Of (Target);
         Ignored_Removed : Boolean;
      begin
         if Is_There (Target) then
            return Restore_Taken;
         end if;
         --  Explorer recreates the folders the item was in.
         if Parent /= "" and then not Hostkit.Fs.Create_Path (Parent) then
            return Restore_Failed;
         end if;
         if Hostkit.Fs.Move_No_Replace_Outcome (From, Target) /= Hostkit.Fs.Moved then
            return (if Is_There (Target) then Restore_Taken else Restore_Failed);
         end if;
         Ignored_Removed := Hostkit.Fs.Delete_File (To_String (Item.Info_Path));
         Notify_Changed (Parent_Of (From));
         Notify_Changed (Parent);
         return Restored;
      end;
   exception
      when others =>
         return Restore_Failed;
   end Restore;

   function Purge (Recycled_Path : String) return Boolean is
      Path : constant String := Normalized (Recycled_Path);
   begin
      if not Is_Recycled_Item (Path) then
         return False;
      end if;
      declare
         Info : constant String := Join (Parent_Of (Path), Format.Info_Name_Of (Leaf_Of (Path)));
         Gone : Boolean;
      begin
         if not Is_There (Path) then
            Gone := True;
         elsif Is_Folder (Path) then
            Gone := Hostkit.Fs.Delete_Tree_No_Follow (Path) = Hostkit.Fs.Tree_Deleted;
         else
            --  A file, or a link -- removed, never followed.
            Gone := Hostkit.Fs.Delete_File (Path);
         end if;
         if Gone and then Is_There (Info) then
            Gone := Hostkit.Fs.Delete_File (Info);
         end if;
         Notify_Changed (Parent_Of (Path));
         return Gone;
      end;
   exception
      when others =>
         return False;
   end Purge;

end Hostkit.Trash;
