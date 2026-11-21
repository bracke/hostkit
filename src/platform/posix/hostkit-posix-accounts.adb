with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C.Strings;

with Hostkit.Posix_Abi;

package body Hostkit.Posix.Accounts is

   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.size_t;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_Size is Interfaces.C.size_t;

   --  ERANGE and EINTR, the same number on Linux and macOS.
   E_Range : constant C_Int := 34;
   E_Intr  : constant C_Int := 4;

   --  Where a lookup's buffer starts when the host suggests nothing, and how
   --  far it may grow. A group with thousands of members needs more than the
   --  suggested size, which is what the growing is for; past the cap the
   --  entry is treated as unreadable rather than allocated without end.
   Default_Size : constant C_Size := 16 * 1_024;
   Least_Size   : constant C_Size := 1_024;
   Largest_Size : constant C_Size := 4 * 1_024 * 1_024;

   --  struct group: the same on both hosts.
   type Group_Record is record
      Name     : System.Address := System.Null_Address;
      Password : System.Address := System.Null_Address;
      Group_Id : Interfaces.C.unsigned := 0;
      Members  : System.Address := System.Null_Address;
   end record
     with Convention => C;

   function Sysconf (Name : C_Int) return Interfaces.C.long
     with Import => True, Convention => C, External_Name => "sysconf";

   function Getpwnam_R
     (Name   : Interfaces.C.char_array;
      Item   : System.Address;
      Buffer : System.Address;
      Size   : C_Size;
      Result : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "getpwnam_r";

   function Getpwuid_R
     (Id     : Interfaces.C.unsigned;
      Item   : System.Address;
      Buffer : System.Address;
      Size   : C_Size;
      Result : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "getpwuid_r";

   function Getgrnam_R
     (Name   : Interfaces.C.char_array;
      Item   : System.Address;
      Buffer : System.Address;
      Size   : C_Size;
      Result : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "getgrnam_r";

   function Getgrgid_R
     (Id     : Interfaces.C.unsigned;
      Item   : System.Address;
      Buffer : System.Address;
      Size   : C_Size;
      Result : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "getgrgid_r";

   type Byte_Buffer is array (C_Size range <>) of Interfaces.C.char;
   type Byte_Buffer_Access is access Byte_Buffer;

   procedure Free is new Ada.Unchecked_Deallocation (Byte_Buffer, Byte_Buffer_Access);

   --  The size the host suggests for the buffer of Name (a _SC_GET*_R_SIZE_MAX),
   --  kept within what this package allows.
   function First_Size (Name : C_Int) return C_Size is
      Suggested : constant Interfaces.C.long := Sysconf (Name);
   begin
      if Suggested <= 0 then
         return Default_Size;
      elsif Suggested > Interfaces.C.long (Largest_Size) then
         return Largest_Size;
      else
         return C_Size'Max (C_Size (Suggested), Least_Size);
      end if;
   end First_Size;

   function To_Chars is new Ada.Unchecked_Conversion (System.Address, Interfaces.C.Strings.chars_ptr);

   --  The C text at Address, or "" for none. Only while the buffer it points
   --  into is still there.
   function Text_At (Address : System.Address) return String is
     (if Address = System.Null_Address then ""
      else Interfaces.C.Strings.Value (To_Chars (Address)));

   --  One reentrant lookup, retried with a larger buffer for as long as the
   --  host says the one it had was too small (ERANGE), and again when a
   --  signal interrupted it. Take is handed the record while the buffer its
   --  strings point into still exists.
   generic
      type Record_Type is private;
      Size_Name : C_Int;
      with function Lookup
        (Item   : System.Address;
         Buffer : System.Address;
         Size   : C_Size;
         Result : System.Address) return C_Int;
      with procedure Take (Item : Record_Type);
   function Look_Up return Boolean;

   function Look_Up return Boolean is
      Size   : C_Size := First_Size (Size_Name);
      Buffer : Byte_Buffer_Access;
      Code   : C_Int;
   begin
      loop
         Buffer := new Byte_Buffer (1 .. Size);

         declare
            Item   : aliased Record_Type;
            Result : aliased System.Address := System.Null_Address;
         begin
            Code := Lookup (Item'Address, Buffer.all'Address, Size, Result'Address);

            if Code = 0 then
               --  0 with no result is "no such entry", not a failure.
               if Result /= System.Null_Address then
                  Take (Item);
               end if;
               Free (Buffer);
               return Result /= System.Null_Address;
            end if;
         end;

         Free (Buffer);

         if Code = E_Range and then Size < Largest_Size then
            Size := C_Size'Min (Size * 2, Largest_Size);
         elsif Code /= E_Intr then
            return False;
         end if;
      end loop;
   exception
      when others =>
         Free (Buffer);
         return False;
   end Look_Up;

   ------------------
   -- User_By_Name --
   ------------------

   function User_By_Name (Name : String) return User_Entry is
      C_Name : constant Interfaces.C.char_array := Interfaces.C.To_C (Name);
      Answer : User_Entry;

      function Lookup
        (Item : System.Address; Buffer : System.Address; Size : C_Size; Result : System.Address) return C_Int
      is (Getpwnam_R (C_Name, Item, Buffer, Size, Result));

      procedure Take (Item : Hostkit.Posix_Abi.Passwd_Record) is
      begin
         Answer :=
           (Found    => True,
            User_Id  => Item.User_Id,
            Group_Id => Item.Group_Id,
            Name     => To_Unbounded_String (Text_At (Item.Name)),
            Home     => To_Unbounded_String (Text_At (Item.Home)));
      end Take;

      function Find is new Look_Up
        (Hostkit.Posix_Abi.Passwd_Record, Hostkit.Posix_Abi.SC_Getpw_R_Size_Max, Lookup, Take);
   begin
      if Name = "" or else not Find then
         return (others => <>);
      end if;

      return Answer;
   end User_By_Name;

   ----------------
   -- User_By_Id --
   ----------------

   function User_By_Id (Id : Interfaces.C.unsigned) return User_Entry is
      Answer : User_Entry;

      function Lookup
        (Item : System.Address; Buffer : System.Address; Size : C_Size; Result : System.Address) return C_Int
      is (Getpwuid_R (Id, Item, Buffer, Size, Result));

      procedure Take (Item : Hostkit.Posix_Abi.Passwd_Record) is
      begin
         Answer :=
           (Found    => True,
            User_Id  => Item.User_Id,
            Group_Id => Item.Group_Id,
            Name     => To_Unbounded_String (Text_At (Item.Name)),
            Home     => To_Unbounded_String (Text_At (Item.Home)));
      end Take;

      function Find is new Look_Up
        (Hostkit.Posix_Abi.Passwd_Record, Hostkit.Posix_Abi.SC_Getpw_R_Size_Max, Lookup, Take);
   begin
      if not Find then
         return (others => <>);
      end if;

      return Answer;
   end User_By_Id;

   -------------------
   -- Group_By_Name --
   -------------------

   function Group_By_Name (Name : String) return Group_Entry is
      C_Name : constant Interfaces.C.char_array := Interfaces.C.To_C (Name);
      Answer : Group_Entry;

      function Lookup
        (Item : System.Address; Buffer : System.Address; Size : C_Size; Result : System.Address) return C_Int
      is (Getgrnam_R (C_Name, Item, Buffer, Size, Result));

      procedure Take (Item : Group_Record) is
      begin
         Answer :=
           (Found    => True,
            Group_Id => Item.Group_Id,
            Name     => To_Unbounded_String (Text_At (Item.Name)));
      end Take;

      function Find is new Look_Up (Group_Record, Hostkit.Posix_Abi.SC_Getgr_R_Size_Max, Lookup, Take);
   begin
      if Name = "" or else not Find then
         return (others => <>);
      end if;

      return Answer;
   end Group_By_Name;

   -----------------
   -- Group_By_Id --
   -----------------

   function Group_By_Id (Id : Interfaces.C.unsigned) return Group_Entry is
      Answer : Group_Entry;

      function Lookup
        (Item : System.Address; Buffer : System.Address; Size : C_Size; Result : System.Address) return C_Int
      is (Getgrgid_R (Id, Item, Buffer, Size, Result));

      procedure Take (Item : Group_Record) is
      begin
         Answer :=
           (Found    => True,
            Group_Id => Item.Group_Id,
            Name     => To_Unbounded_String (Text_At (Item.Name)));
      end Take;

      function Find is new Look_Up (Group_Record, Hostkit.Posix_Abi.SC_Getgr_R_Size_Max, Lookup, Take);
   begin
      if not Find then
         return (others => <>);
      end if;

      return Answer;
   end Group_By_Id;

end Hostkit.Posix.Accounts;
