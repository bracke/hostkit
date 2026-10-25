with Interfaces;
with Interfaces.C;

--  Pieces of the Linux kernel ABI that more than one Linux body needs: the
--  statx(2) record, and the open(2) flags whose values depend on the machine.
--
--  In the shared source rather than src/platform/linux for two reasons. Two
--  bodies need the same layout, and each had grown its own copy -- one of them
--  with C long for the 64-bit fields, which is 32 bits on 32-bit Linux and
--  shifts every field after the first. And the choice of flag values is pure
--  logic over a machine name, which a test on any host can feed "aarch64".
--  Nothing here is called on another host; it only declares.
package Hostkit.Linux_Abi is

   subtype C_Int is Interfaces.C.int;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   --  statx uses fixed-width __u64/__s64 fields, never C long.
   subtype C_U64 is Interfaces.Unsigned_64;
   subtype C_S64 is Interfaces.Integer_64;

   type U16_Array is array (Positive range <>) of C_U16 with Convention => C;
   type U64_Array is array (Positive range <>) of C_U64 with Convention => C;

   type Statx_Timestamp is record
      Seconds     : C_S64 := 0;
      Nanoseconds : C_U32 := 0;
      Reserved    : C_U32 := 0;
   end record with Convention => C;

   --  struct statx, all 256 bytes of it.
   type Statx_Record is record
      Mask                   : C_U32 := 0;
      Block_Size             : C_U32 := 0;
      Attributes             : C_U64 := 0;
      Link_Count             : C_U32 := 0;
      User_Id                : C_U32 := 0;
      Group_Id               : C_U32 := 0;
      Mode                   : C_U16 := 0;
      Spare_0                : U16_Array (1 .. 1) := [others => 0];
      Inode                  : C_U64 := 0;
      Size                   : C_U64 := 0;
      Blocks                 : C_U64 := 0;
      Attributes_Mask        : C_U64 := 0;
      Access_Time            : Statx_Timestamp;
      Birth_Time             : Statx_Timestamp;
      Change_Time            : Statx_Timestamp;
      Modified_Time          : Statx_Timestamp;
      Special_Device_Major   : C_U32 := 0;
      Special_Device_Minor   : C_U32 := 0;
      Device_Major           : C_U32 := 0;
      Device_Minor           : C_U32 := 0;
      Mount_Id               : C_U64 := 0;
      Direct_Io_Memory_Align : C_U32 := 0;
      Direct_Io_Offset_Align : C_U32 := 0;
      Spare_3                : U64_Array (1 .. 12) := [others => 0];
   end record with Convention => C;

   At_Empty_Path : constant C_Int := 16#1000#;
   Statx_Mode    : constant C_U32 := 16#2#;
   Statx_Uid     : constant C_U32 := 16#8#;

   --  Flags with one value on every Linux machine.
   O_Nonblock : constant C_Int := 16#800#;
   O_Cloexec  : constant C_Int := 16#8_0000#;
   O_Noatime  : constant C_Int := 16#4_0000#;
   O_Path     : constant C_Int := 16#20_0000#;

   --  asm-generic/fcntl.h is right for x86, riscv and most targets, but arm,
   --  arm64, powerpc and m68k define their own O_DIRECTORY and O_NOFOLLOW (and
   --  give the generic O_NOFOLLOW bit to O_LARGEFILE), so a hard-coded x86
   --  value silently follows a final symlink there.
   --
   --  @param Machine The uname machine field (Hostkit.Host.Machine_Name).
   --  @return True when Machine uses the arm/powerpc/m68k values.
   function Uses_Alternate_Open_Flags (Machine : String) return Boolean;

   --  O_DIRECTORY for Machine.
   function O_Directory (Machine : String) return C_Int is
     (if Uses_Alternate_Open_Flags (Machine) then 16#4000# else 16#1_0000#);

   --  O_NOFOLLOW for Machine.
   function O_Nofollow (Machine : String) return C_Int is
     (if Uses_Alternate_Open_Flags (Machine) then 16#8000# else 16#2_0000#);

end Hostkit.Linux_Abi;
