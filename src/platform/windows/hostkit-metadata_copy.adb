with Hostkit.Errors;
with Hostkit.Windows_Paths;
with Interfaces.C;
with System;
with System.Storage_Elements;

package body Hostkit.Metadata_Copy is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.Unsigned_64;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;

   type Filetime is record
      Low, High : C_DWord;
   end record with Convention => C;

   type By_Handle_File_Information is record
      Attributes : C_DWord;
      Creation, Accessed, Modified : Filetime;
      Volume_Serial, Size_High, Size_Low, Link_Count : C_DWord;
      File_Index_High, File_Index_Low : C_DWord;
   end record with Convention => C;

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (-1);
   File_Read_Attributes  : constant C_DWord := 16#0000_0080#;
   File_Write_Attributes : constant C_DWord := 16#0000_0100#;
   File_Share_All : constant C_DWord := 7;
   Open_Existing : constant C_DWord := 3;
   File_Flag_Backup_Semantics : constant C_DWord := 16#0200_0000#;
   File_Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;

   function Wide (Value : String) return Wide_String renames Hostkit.Windows_Paths.Native;

   function Create_File_W
     (Name : System.Address; Access_Mode, Share : C_DWord;
      Security : System.Address; Disposition, Flags : C_DWord;
      Template : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";
   function Close_Handle (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";
   function Get_File_Time
     (Handle : System.Address; Created : System.Address;
      Accessed, Modified : access Filetime) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileTime";
   function Set_File_Time
     (Handle : System.Address; Created : System.Address;
      Accessed, Modified : access Filetime) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetFileTime";
   function Get_File_Information
     (Handle : System.Address;
      Info : access By_Handle_File_Information) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetFileInformationByHandle";

   function Get_Last_Error return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLastError";
   function Get_File_Attributes_W (Path : System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesW";
   function Set_File_Attributes_W (Path : System.Address; Attributes : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetFileAttributesW";
   function Encrypt_File_W (Path : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "EncryptFileW";

   Attribute_Reparse_Point : constant C_DWord := 16#0400#;
   Attribute_Encrypted     : constant C_DWord := 16#4000#;
   Invalid_File_Attributes : constant C_DWord := 16#FFFF_FFFF#;

   --  WIN32_FIND_STREAM_DATA: the stream's size, then its name as
   --  ":name:$DATA" (MAX_PATH + 36 UTF-16 units, NUL-terminated).
   type Stream_Name is array (1 .. 296) of Wide_Character with Convention => C;
   type Find_Stream_Data is record
      Size : Interfaces.Integer_64;
      Name : Stream_Name;
   end record with Convention => C;

   function Find_First_Stream_W
     (Path : System.Address; Level : C_Int; Data : access Find_Stream_Data; Flags : C_DWord)
      return System.Address
     with Import, Convention => Stdcall, External_Name => "FindFirstStreamW";
   function Find_Next_Stream_W (Find : System.Address; Data : access Find_Stream_Data) return C_Int
     with Import, Convention => Stdcall, External_Name => "FindNextStreamW";
   function Find_Close (Find : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "FindClose";
   function Read_File
     (Handle : System.Address; Buffer : System.Address; Size : C_DWord;
      Done : access C_DWord; Overlapped : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "ReadFile";
   function Write_File
     (Handle : System.Address; Buffer : System.Address; Size : C_DWord;
      Done : access C_DWord; Overlapped : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "WriteFile";
   function Get_Volume_Information_By_Handle_W
     (Handle : System.Address; Volume_Name : System.Address; Volume_Name_Size : C_DWord;
      Serial, Max_Component, Flags : access C_DWord;
      File_System_Name : System.Address; File_System_Name_Size : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetVolumeInformationByHandleW";

   function Open_Entry (Path : String; Access_Mode : C_DWord)
      return System.Address
   is
      Name : aliased Wide_String := Wide (Path);
   begin
      return Create_File_W
        (Name'Address, Access_Mode, File_Share_All, System.Null_Address,
         Open_Existing,
         File_Flag_Backup_Semantics + File_Flag_Open_Reparse_Point,
         System.Null_Address);
   exception
      when others =>
         return Invalid_Handle;
   end Open_Entry;

   function Value (Item : Filetime) return Interfaces.Integer_64 is
      Raw : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Item.High) * 2 ** 32
        + Interfaces.Unsigned_64 (Item.Low);
   begin
      return Interfaces.Integer_64 (Raw);
   end Value;

   function File_Time (Value : Interfaces.Integer_64) return Filetime is
      Raw : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
   begin
      return
        (Low => C_DWord (Raw and 16#FFFF_FFFF#),
         High => C_DWord (Raw / 2 ** 32));
   end File_Time;

   function Capture_Times
     (Path : String; Times : out Entry_Times) return Boolean
   is
      Handle : constant System.Address := Open_Entry (Path, File_Read_Attributes);
      Accessed, Modified : aliased Filetime;
      Ok : constant Boolean := Handle /= Invalid_Handle
        and then Get_File_Time
          (Handle, System.Null_Address, Accessed'Access, Modified'Access) /= 0;
      Ignored : C_Int;
   begin
      Times := [others => 0];
      if Ok then
         Times := [Value (Accessed), 0, Value (Modified), 0];
      end if;
      if Handle /= Invalid_Handle then
         Ignored := Close_Handle (Handle);
      end if;
      return Ok;
   exception
      when others =>
         Times := [others => 0];
         return False;
   end Capture_Times;

   function Apply_Times
     (Path : String; Times : Entry_Times) return Boolean
   is
      Handle : constant System.Address := Open_Entry (Path, File_Write_Attributes);
      Accessed : aliased Filetime := File_Time (Times (1));
      Modified : aliased Filetime := File_Time (Times (3));
      Ok : constant Boolean := Handle /= Invalid_Handle
        and then Set_File_Time
          (Handle, System.Null_Address, Accessed'Access, Modified'Access) /= 0;
      Ignored : C_Int;
   begin
      if not Ok then
         --  The open's or SetFileTime's own reason, before CloseHandle.
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      if Handle /= Invalid_Handle then
         Ignored := Close_Handle (Handle);
      end if;
      return Ok;
   exception
      when others =>
         return False;
   end Apply_Times;

   --  The names of Path's named data streams, the unnamed "::$DATA" (the
   --  file's own bytes) left out. Best effort, as xattrs are listed: a volume
   --  that keeps no streams (FAT, exFAT) answers none, and so does any other
   --  refusal, with ERROR_HANDLE_EOF the usual answer for an entry that has
   --  none.
   procedure Capture_Streams (Path : String; Streams : in out Attribute_Vectors.Vector) is
      Wide_Path : aliased constant Wide_String := Wide (Path);
      Data      : aliased Find_Stream_Data;
      Find      : constant System.Address :=
        Find_First_Stream_W (Wide_Path'Address, 0, Data'Access, 0);
      Ignored   : C_Int;
   begin
      if Find = Invalid_Handle then
         return;
      end if;
      loop
         declare
            Last : Natural := 0;
         begin
            while Last < Data.Name'Last and then Data.Name (Last + 1) /= Wide_Character'Val (0) loop
               Last := Last + 1;
            end loop;
            declare
               Name : Wide_String (1 .. Last);
            begin
               for Index in Name'Range loop
                  Name (Index) := Data.Name (Index);
               end loop;
               if Name /= "::$DATA" then
                  Streams.Append
                    (Attribute'(Name  => To_Unbounded_String (Hostkit.Windows_Paths.To_UTF_8 (Name)),
                                Value => Null_Unbounded_String));
               end if;
            end;
         end;
         exit when Find_Next_Stream_W (Find, Data'Access) = 0;
      end loop;
      Ignored := Find_Close (Find);
   exception
      when others =>
         Ignored := Find_Close (Find);
         raise;
   end Capture_Streams;

   function Capture (Path : String) return Snapshot is
      Handle : constant System.Address := Open_Entry (Path, File_Read_Attributes);
      Info : aliased By_Handle_File_Information;
      Accessed, Modified : aliased Filetime;
      Result : Snapshot;
      Ignored : C_Int;
   begin
      Result.Available := Handle /= Invalid_Handle
        and then Get_File_Time
          (Handle, System.Null_Address, Accessed'Access, Modified'Access) /= 0
        and then Get_File_Information (Handle, Info'Access) /= 0;
      if Result.Available then
         Result.Times := [Value (Accessed), 0, Value (Modified), 0];
         Result.Links := Interfaces.Unsigned_64 (Info.Link_Count);
         --  Windows has no mode: its file attributes stand in for it.
         Result.Mode := Interfaces.Unsigned_64 (Info.Attributes);
         Result.Is_Link := (Info.Attributes and Attribute_Reparse_Point) /= 0;
         Result.Encrypted := not Result.Is_Link and then (Info.Attributes and Attribute_Encrypted) /= 0;
      end if;
      if Handle /= Invalid_Handle then
         Ignored := Close_Handle (Handle);
      end if;
      --  A link's streams are its target's to keep: FindFirstStreamW
      --  follows it.
      if Result.Available and then not Result.Is_Link then
         Result.Source := To_Unbounded_String (Path);
         Capture_Streams (Path, Result.Streams);
      end if;
      return Result;
   exception
      when others =>
         return No_Snapshot;
   end Capture;

   function Is_Available (Item : Snapshot) return Boolean is (Item.Available);
   function Link_Count (Item : Snapshot) return Interfaces.Unsigned_64 is (Item.Links);

   procedure Set_Times (Item : in out Snapshot; Times : Entry_Times) is
   begin
      Item.Times := Times;
   end Set_Times;

   --  Copy each named stream of Item's source onto Path. A destination
   --  volume without named streams takes the entry without them, as cp -a
   --  copies onto one without xattrs; a stream gone from the source since
   --  Capture is left out. Any other failure is the copy's, with errno set.
   function Copy_Streams (Item : Snapshot; Path : String) return Boolean is
      File_Named_Streams      : constant C_DWord := 16#0004_0000#;
      Generic_Read            : constant C_DWord := 16#8000_0000#;
      Generic_Write           : constant C_DWord := 16#4000_0000#;
      Create_New              : constant C_DWord := 1;
      Error_File_Not_Found    : constant C_DWord := 2;
      Error_Not_Supported     : constant C_DWord := 50;
      Error_Invalid_Parameter : constant C_DWord := 87;
      Error_Invalid_Name      : constant C_DWord := 123;

      --  Whether the volume holding Path keeps named streams; True when it
      --  will not say, and the stream's own open decides.
      function Volume_Keeps_Streams return Boolean is
         Handle  : constant System.Address := Open_Entry (Path, File_Read_Attributes);
         Serial, Max_Component, Flags : aliased C_DWord := 0;
         Known   : Boolean;
         Ignored : C_Int;
      begin
         if Handle = Invalid_Handle then
            return True;
         end if;
         Known := Get_Volume_Information_By_Handle_W
           (Handle, System.Null_Address, 0, Serial'Access, Max_Component'Access, Flags'Access,
            System.Null_Address, 0) /= 0;
         Ignored := Close_Handle (Handle);
         return not Known or else (Flags and File_Named_Streams) /= 0;
      end Volume_Keeps_Streams;

      function Open_Stream (Name : String; Access_Mode, Disposition : C_DWord) return System.Address is
         Wide_Name : aliased constant Wide_String := Wide (Name);
      begin
         return Create_File_W
           (Wide_Name'Address, Access_Mode,
            (if Disposition = Open_Existing then File_Share_All else 0),
            System.Null_Address, Disposition, File_Flag_Backup_Semantics, System.Null_Address);
      end Open_Stream;

      Source  : constant String := To_String (Item.Source);
      Input   : System.Address := Invalid_Handle;
      Output  : System.Address := Invalid_Handle;
      Buffer  : aliased String (1 .. 16_384);
      Read, Written : aliased C_DWord;
      Ignored : C_Int;
   begin
      if Item.Streams.Is_Empty or else not Volume_Keeps_Streams then
         return True;
      end if;
      for Stream of Item.Streams loop
         declare
            Name : constant String := To_String (Stream.Name);
         begin
            Input := Open_Stream (Source & Name, Generic_Read, Open_Existing);
            if Input = Invalid_Handle then
               if Get_Last_Error /= Error_File_Not_Found then
                  Hostkit.Errors.Set_Errno_From_Last_Error;
                  return False;
               end if;
            else
               Output := Open_Stream (Path & Name, Generic_Write, Create_New);
               if Output = Invalid_Handle then
                  declare
                     Error : constant C_DWord := Get_Last_Error;
                  begin
                     if Error in Error_Invalid_Name | Error_Not_Supported | Error_Invalid_Parameter then
                        --  This volume takes no stream after all.
                        Ignored := Close_Handle (Input);
                        return True;
                     end if;
                     Hostkit.Errors.Set_Errno_From_Last_Error;
                  end;
                  Ignored := Close_Handle (Input);
                  return False;
               end if;
               loop
                  if Read_File (Input, Buffer'Address, Buffer'Length, Read'Access, System.Null_Address) = 0 then
                     Hostkit.Errors.Set_Errno_From_Last_Error;
                     Ignored := Close_Handle (Input);
                     Ignored := Close_Handle (Output);
                     return False;
                  end if;
                  exit when Read = 0;
                  if Write_File (Output, Buffer'Address, Read, Written'Access, System.Null_Address) = 0
                    or else Written /= Read
                  then
                     Hostkit.Errors.Set_Errno_From_Last_Error;
                     Ignored := Close_Handle (Input);
                     Ignored := Close_Handle (Output);
                     return False;
                  end if;
               end loop;
               Ignored := Close_Handle (Input);
               Input := Invalid_Handle;
               if Close_Handle (Output) = 0 then
                  Output := Invalid_Handle;
                  Hostkit.Errors.Set_Errno_From_Last_Error;
                  return False;
               end if;
               Output := Invalid_Handle;
            end if;
         end;
      end loop;
      return True;
   exception
      when others =>
         if Input /= Invalid_Handle then
            Ignored := Close_Handle (Input);
         end if;
         if Output /= Invalid_Handle then
            Ignored := Close_Handle (Output);
         end if;
         return False;
   end Copy_Streams;

   function Apply
     (Item : Snapshot; Path : String; Preserve_Ownership : Boolean)
      return Boolean
   is
      pragma Unreferenced (Preserve_Ownership);
      --  What a user sets and a copy keeps: read-only, hidden, system,
      --  archive, not indexed. Others (compressed, encrypted, sparse) are
      --  the volume's to give, not an attribute to write.
      Kept : constant Interfaces.Unsigned_64 := 16#0001# + 16#0002# + 16#0004# + 16#0020# + 16#2000#;
      Wide_Path : aliased constant Wide_String := Wide (Path);
   begin
      --  Streams first: writing one moves the entry's modification time,
      --  and a read-only entry takes none.
      if not Item.Available or else not Copy_Streams (Item, Path) then
         return False;
      end if;
      --  An encrypted file was created encrypted (Create_New's Encrypted),
      --  so its bytes never reached the disk in the clear; a directory is
      --  marked here, which encrypts nothing it already holds and everything
      --  made in it later. A volume without EFS refuses, and the copy fails
      --  rather than arriving decrypted.
      if Item.Encrypted then
         declare
            Current : constant C_DWord := Get_File_Attributes_W (Wide_Path'Address);
         begin
            if Current = Invalid_File_Attributes
              or else ((Current and Attribute_Encrypted) = 0 and then Encrypt_File_W (Wide_Path'Address) = 0)
            then
               Hostkit.Errors.Set_Errno_From_Last_Error;
               return False;
            end if;
         end;
      end if;
      if not Apply_Times (Path, Item.Times) then
         return False;
      end if;
      --  Last: a read-only entry's times could not be set after it.
      if Set_File_Attributes_W (Wide_Path'Address, C_DWord (Item.Mode and Kept)) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      return True;
   end Apply;
end Hostkit.Metadata_Copy;
