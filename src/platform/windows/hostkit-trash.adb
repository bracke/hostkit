with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Conversions;
with Interfaces;
with Interfaces.C;
with System;

package body Hostkit.Trash is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_short;

   type SH_File_Operation_W is record
      Window        : System.Address := System.Null_Address;
      Function_Code : Interfaces.C.unsigned := 0;
      From          : System.Address := System.Null_Address;
      To_Path       : System.Address := System.Null_Address;
      Flags         : Interfaces.C.unsigned_short := 0;
      Any_Aborted   : Interfaces.C.int := 0;
      Name_Mappings : System.Address := System.Null_Address;
      Progress_Title : System.Address := System.Null_Address;
   end record
     with Convention => C;

   function SHFileOperationW
     (Operation : access SH_File_Operation_W)
      return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "SHFileOperationW";

   FO_Delete : constant Interfaces.C.unsigned := 3;

   --  ALLOW_UNDO is the flag that makes this a trash rather than a delete:
   --  without it the shell removes the file outright. The other three keep the
   --  shell's own dialogs out of an application that is drawing its own.
   FOF_Silent : constant Interfaces.C.unsigned_short := 16#0004#;
   FOF_No_Confirmation : constant Interfaces.C.unsigned_short := 16#0010#;
   FOF_Allow_Undo : constant Interfaces.C.unsigned_short := 16#0040#;
   FOF_No_Error_UI : constant Interfaces.C.unsigned_short := 16#0400#;
   --  The one prompt kept: should the shell destroy the item after all (one
   --  too big for the bin, a bin set to delete at once), the user is asked
   --  first and may cancel, which leaves it where it was.
   FOF_Want_Nuke_Warning : constant Interfaces.C.unsigned_short := 16#4000#;

   function Get_Volume_Path_Name_W
     (File_Name   : System.Address;
      Volume_Path : System.Address;
      Length      : Interfaces.C.unsigned_long)
      return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "GetVolumePathNameW";

   function Get_Drive_Type_W (Root : System.Address) return Interfaces.C.unsigned
     with Import, Convention => Stdcall, External_Name => "GetDriveTypeW";

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

   function Current return Facility is
   begin
      return
        (Available             => True,
         Api_Name              => To_Unbounded_String ("SHFileOperationW"),
         Uses_Recycle_Bin      => True,
         Preserves_Metadata    => True,
         Requires_User_Consent => False);
   end Current;

   function Move_To_Trash (Path : String) return Boolean is
      --  SHFileOperationW expects UTF-16 (16-bit WCHAR). GNAT Wide_String is
      --  16-bit per element, so decode the UTF-8 path to Wide_String and
      --  double-NUL terminate it (pFrom is a double-null-terminated list).
      Wide_Path : aliased Wide_String :=
        Ada.Strings.UTF_Encoding.Conversions.Convert (Path)
          & Wide_Character'Val (0) & Wide_Character'Val (0);
      Operation : aliased SH_File_Operation_W :=
        (Window        => System.Null_Address,
         Function_Code => FO_Delete,
         From          => Wide_Path'Address,
         To_Path       => System.Null_Address,
         Flags         =>
           FOF_Allow_Undo or FOF_No_Confirmation or FOF_No_Error_UI or FOF_Silent or FOF_Want_Nuke_Warning,
         Any_Aborted   => 0,
         Name_Mappings => System.Null_Address,
         Progress_Title => System.Null_Address);
      Status : constant Interfaces.C.int := SHFileOperationW (Operation'Access);
   begin
      --  The shell reports a user or shell abort separately from its status, and
      --  an aborted operation left the file where it was.
      return Status = 0 and then Operation.Any_Aborted = 0;
   exception
      when others =>
         return False;
   end Move_To_Trash;

   function Can_Hold (Path : String) return Boolean is
      use type Interfaces.C.long;
      use type Interfaces.C.unsigned;
      Wide_Path : aliased constant Wide_String :=
        Ada.Strings.UTF_Encoding.Conversions.Convert (Path) & Wide_Character'Val (0);
      Root : aliased Wide_String (1 .. 32_768) := [others => Wide_Character'Val (0)];
      Info : aliased Recycle_Bin_Info;
   begin
      --  A share named by its UNC path (\\server\share) has no bin.
      if Path'Length >= 2 and then Path (Path'First) in '\' | '/' and then Path (Path'First + 1) in '\' | '/' then
         return False;
      end if;
      if Get_Volume_Path_Name_W (Wide_Path'Address, Root'Address, Root'Length) = 0
        or else Get_Drive_Type_W (Root'Address) /= Drive_Fixed
      then
         return False;
      end if;
      Info.Size_Of := Interfaces.Unsigned_32 (Recycle_Bin_Info'Size / 8);
      return SH_Query_Recycle_Bin_W (Root'Address, Info'Access) = 0;
   exception
      when others =>
         return False;
   end Can_Hold;

end Hostkit.Trash;
