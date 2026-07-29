with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Strings;
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
        Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Path)
          & Wide_Character'Val (0) & Wide_Character'Val (0);
      Operation : aliased SH_File_Operation_W :=
        (Window        => System.Null_Address,
         Function_Code => FO_Delete,
         From          => Wide_Path'Address,
         To_Path       => System.Null_Address,
         Flags         => FOF_Allow_Undo or FOF_No_Confirmation or FOF_No_Error_UI or FOF_Silent,
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

end Hostkit.Trash;
