with Interfaces.C;

--  Pieces of the Darwin ABI that more than one macOS body needs: struct stat
--  in its 64-bit-inode layout -- the only one Apple silicon has, and the one
--  Intel answers through the $INODE64 entry points that Hostkit.Darwin_Symbols
--  names -- and the open(2) flags. Declarations only; each body binds its own
--  calls.
package Hostkit.Darwin_Abi is

   subtype C_Int is Interfaces.C.int;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S32 is Interfaces.C.int;
   subtype C_S64 is Interfaces.C.long;

   type Timespec is record
      Seconds     : C_S64 := 0;
      Nanoseconds : C_S64 := 0;
   end record with Convention => C;

   type Spare_Array is array (1 .. 2) of C_S64 with Convention => C;

   type Stat_Record is record
      Device        : C_S32 := 0;
      Mode          : C_U16 := 0;
      Link_Count    : C_U16 := 0;
      Inode         : C_U64 := 0;
      User_Id       : C_U32 := 0;
      Group_Id      : C_U32 := 0;
      Raw_Device    : C_S32 := 0;
      Padding       : C_S32 := 0;
      Access_Time   : Timespec;
      Modified_Time : Timespec;
      Change_Time   : Timespec;
      Birth_Time    : Timespec;
      Size          : C_S64 := 0;
      Blocks        : C_S64 := 0;
      Block_Size    : C_S32 := 0;
      Flags         : C_U32 := 0;
      Generation    : C_U32 := 0;
      Long_Spare    : C_S32 := 0;
      Quad_Spare    : Spare_Array := [others => 0];
   end record with Convention => C;

   O_Nonblock  : constant C_Int := 16#4#;
   O_Nofollow  : constant C_Int := 16#100#;
   O_Evtonly   : constant C_Int := 16#8000#;
   O_Directory : constant C_Int := 16#10_0000#;
   O_Cloexec   : constant C_Int := 16#100_0000#;

   File_Type_Mask : constant C_U16 := 8#170000#;
   Regular_File   : constant C_U16 := 8#100000#;

end Hostkit.Darwin_Abi;
