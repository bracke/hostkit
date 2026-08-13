with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Locks is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (-1);

   Generic_Read  : constant C_DWord := 16#8000_0000#;
   Generic_Write : constant C_DWord := 16#4000_0000#;

   File_Share_Read  : constant C_DWord := 1;
   File_Share_Write : constant C_DWord := 2;

   Open_Always : constant C_DWord := 4;

   File_Attribute_Normal : constant C_DWord := 16#80#;

   Lockfile_Exclusive_Lock   : constant C_DWord := 2;
   Lockfile_Fail_Immediately : constant C_DWord := 1;

   Error_Lock_Violation : constant C_DWord := 33;
   Error_Sharing_Violation : constant C_DWord := 32;

   type Security_Attributes is record
      Length              : C_DWord := 0;
      Security_Descriptor : System.Address := System.Null_Address;
      Inherit_Handle      : Interfaces.C.int := 0;
   end record
     with Convention => C;

   --  OVERLAPPED. LockFileEx needs one only to say where in the file the lock
   --  starts; the whole structure is zeroed and the offset left at zero, which
   --  locks from the beginning.
   type Overlapped is record
      Internal      : System.Address := System.Null_Address;
      Internal_High : System.Address := System.Null_Address;
      Offset        : C_DWord := 0;
      Offset_High   : C_DWord := 0;
      Event         : System.Address := System.Null_Address;
   end record
     with Convention => C;

   function Create_File
     (Name        : System.Address;
      Access_Mode : C_DWord;
      Share_Mode  : C_DWord;
      Security    : System.Address;
      Disposition : C_DWord;
      Attributes  : C_DWord;
      Template    : System.Address) return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

   function Close_Handle (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

   function Lock_File_Ex
     (Handle       : System.Address;
      Flags        : C_DWord;
      Reserved     : C_DWord;
      Bytes_Low    : C_DWord;
      Bytes_High   : C_DWord;
      Region       : access Overlapped) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "LockFileEx";

   function Unlock_File_Ex
     (Handle     : System.Address;
      Reserved   : C_DWord;
      Bytes_Low  : C_DWord;
      Bytes_High : C_DWord;
      Region     : access Overlapped) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "UnlockFileEx";

   function Get_Last_Error return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetLastError";

   function Wide (Value : String) return Wide_String
   is (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

   function To_Handle (Value : Interfaces.Integer_64) return System.Address
   is (System.Storage_Elements.To_Address
         (System.Storage_Elements.Integer_Address (Value)));

   -------------
   -- Acquire --
   -------------

   function Acquire
     (Path : String;
      Kind : Lock_Kind;
      Wait : Boolean;
      Item : out Lock) return Lock_Outcome
   is
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : aliased Security_Attributes;
      Handle     : System.Address;
      Region     : aliased Overlapped;
      Flags      : C_DWord := 0;
      Ignored    : Interfaces.C.int;
   begin
      Item.Handle := -1;
      Item.Held   := False;

      Attributes.Length := C_DWord (Security_Attributes'Size / 8);
      Attributes.Inherit_Handle := 0;

      --  OPEN_ALWAYS, not CREATE_ALWAYS: a lock taken on the state file itself
      --  must not destroy the state it is protecting. The share mode is
      --  permissive on purpose -- exclusion here comes from LockFileEx, which
      --  is advisory and which another holder can wait on, rather than from
      --  denying the open outright, which it could not.
      Handle := Create_File
        (Wide_Path'Address,
         Generic_Read + Generic_Write,
         File_Share_Read + File_Share_Write,
         Attributes'Address,
         Open_Always,
         File_Attribute_Normal,
         System.Null_Address);

      if Handle = Invalid_Handle then
         return Lock_Error;
      end if;

      if Kind = Lock_Exclusive then
         Flags := Flags + Lockfile_Exclusive_Lock;
      end if;

      if not Wait then
         Flags := Flags + Lockfile_Fail_Immediately;
      end if;

      --  The whole file, as far as it can be addressed. Locking a byte range
      --  larger than the file is allowed and is how a whole-file lock is
      --  spelled here; the file being empty does not make the lock empty.
      if Lock_File_Ex (Handle, Flags, 0, 16#FFFF_FFFF#, 16#FFFF_FFFF#,
                       Region'Access) = 0
      then
         declare
            Code : constant C_DWord := Get_Last_Error;
         begin
            Ignored := Close_Handle (Handle);

            if Code = Error_Lock_Violation or else Code = Error_Sharing_Violation then
               return Lock_Busy;
            end if;

            return Lock_Error;
         end;
      end if;

      Item.Handle := Interfaces.Integer_64
        (System.Storage_Elements.To_Integer (Handle));
      Item.Held := True;

      return Lock_Ok;
   end Acquire;

   -------------
   -- Release --
   -------------

   procedure Release (Item : in out Lock) is
      Region  : aliased Overlapped;
      Ignored : Interfaces.C.int;
   begin
      if not Item.Held then
         return;
      end if;

      Ignored := Unlock_File_Ex
        (To_Handle (Item.Handle), 0, 16#FFFF_FFFF#, 16#FFFF_FFFF#, Region'Access);
      Ignored := Close_Handle (To_Handle (Item.Handle));

      Item.Handle := -1;
      Item.Held   := False;
   end Release;

   -------------
   -- Is_Held --
   -------------

   function Is_Held (Item : Lock) return Boolean is
   begin
      return Item.Held;
   end Is_Held;

end Hostkit.Locks;
