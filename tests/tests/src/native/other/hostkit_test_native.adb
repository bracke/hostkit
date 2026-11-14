with Interfaces.C;

with GNAT.OS_Lib;

with Hostkit.Host;
with Hostkit.Metadata;

--  A host with modes and no share modes: nothing can hold a file against
--  writers here, and read-only is a mode without a write bit.
package body Hostkit_Test_Native is

   function Hold_Against_Writers (Path : String; Held : out Exclusive_Hold) return Boolean is
      pragma Unreferenced (Path);
   begin
      Held.Handle := System.Null_Address;
      return False;
   end Hold_Against_Writers;

   procedure Release (Held : in out Exclusive_Hold) is
   begin
      Held.Handle := System.Null_Address;
   end Release;

   function Is_Read_Only (Path : String) return Boolean is
      use type Interfaces.Unsigned_32;
      Write_Bits : constant Interfaces.Unsigned_32 := 8#222#;
      Available  : Boolean;
      Bits       : constant Natural := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   begin
      return Available and then (Interfaces.Unsigned_32 (Bits) and Write_Bits) = 0;
   end Is_Read_Only;

   function Create_With_Units (Folder : String; Leaf : Wide_String) return Boolean is
      pragma Unreferenced (Folder, Leaf);
   begin
      return False;
   end Create_With_Units;

   function Handle_Inheritance (Handle : Interfaces.Integer_64; Inheritable : out Boolean) return Boolean is
      pragma Unreferenced (Handle);
   begin
      Inheritable := False;
      return False;
   end Handle_Inheritance;

   function Drop_Backup_Privileges return Boolean is (True);

   function Await_Exit_Uncollected (Process_Id : Integer) return Exit_Wait is
      use type Interfaces.C.int;
      use type Hostkit.Host.Kind;

      --  siginfo_t: 128 bytes on Linux, less on macOS; only its room matters
      --  here, never a field.
      type Signal_Information is array (1 .. 64) of Interfaces.C.int
        with Convention => C;

      --  Not variadic, so an ordinary import on every POSIX host and ABI.
      function C_Waitid
        (Id_Type : Interfaces.C.int;
         Id      : Interfaces.C.unsigned;
         Info    : access Signal_Information;
         Options : Interfaces.C.int) return Interfaces.C.int
        with Import, Convention => C, External_Name => "waitid";

      --  P_PID is 1 on Linux and macOS alike, as are WEXITED (4), EINTR (4)
      --  and ECHILD (10); WNOWAIT is not: Linux's 0x01000000, macOS's 0x20.
      P_Pid    : constant Interfaces.C.int := 1;
      W_Exited : constant Interfaces.C.int := 4;
      W_Nowait : constant Interfaces.C.int :=
        (if Hostkit.Host.Current = Hostkit.Host.MacOS then 16#20# else 16#0100_0000#);
      E_Intr   : constant Integer := 4;
      E_Child  : constant Integer := 10;
      Info     : aliased Signal_Information := [others => 0];
   begin
      if Process_Id <= 0 then
         return Cannot_Wait;
      end if;
      loop
         if C_Waitid (P_Pid, Interfaces.C.unsigned (Process_Id), Info'Access, W_Exited + W_Nowait) = 0 then
            return Exited;
         end if;
         case GNAT.OS_Lib.Errno is
            when E_Intr =>
               null;
            when E_Child =>
               return Not_A_Child;
            when others =>
               return Cannot_Wait;
         end case;
      end loop;
   end Await_Exit_Uncollected;

end Hostkit_Test_Native;
