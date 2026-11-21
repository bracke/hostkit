with Ada.Containers.Vectors;

with Hostkit.Posix_Abi;

package body Hostkit.Posix is
   use type Interfaces.C.int;
   use type Interfaces.Unsigned_64;

   EINTR   : constant Interfaces.C.int := 4;
   WNOHANG : constant Interfaces.C.int := 1;

   --  waitpid (pid, NULL, WNOHANG): that one child, and do not block. It returns
   --  the pid once the child is collected, 0 while it is still running, and -1
   --  when there is no such child to wait for -- someone else collected it.
   function Waitpid
     (Pid     : Interfaces.C.int;
      Status  : System.Address;
      Options : Interfaces.C.int)
      return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "waitpid";

   package Pid_Vectors is new Ada.Containers.Vectors (Positive, Integer);

   --  The detached children not yet collected. Launch notes from the caller's
   --  thread and the reaper collects from its own, so the list is guarded.
   protected Pending is
      procedure Add (Process_Id : Integer);
      procedure Reap;
   private
      Children : Pid_Vectors.Vector;
   end Pending;

   protected body Pending is

      procedure Add (Process_Id : Integer) is
      begin
         Children.Append (Process_Id);
      end Add;

      procedure Reap is
         Index     : Positive := 1;
         Collected : Interfaces.C.int;
      begin
         while Index <= Children.Last_Index loop
            Collected := Waitpid (Interfaces.C.int (Children.Element (Index)), System.Null_Address, WNOHANG);

            --  Still running, or interrupted before it could say: keep it for
            --  the next round. Collected, or no longer ours to collect: forget it.
            if Collected = 0 or else (Collected < 0 and then Errno = EINTR) then
               Index := Index + 1;
            else
               Children.Delete (Index);
            end if;
         end loop;
      end Reap;

   end Pending;

   --  errno is a macro over a per-thread location; the function it expands
   --  to answers that location's address, and its name is the host's.
   function Errno_Location return System.Address
     with Import => True, Convention => C, External_Name => Hostkit.Posix_Abi.Errno_Location;

   -----------
   -- Errno --
   -----------

   function Errno return Interfaces.C.int is
      Value : Interfaces.C.int
        with Import => True, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   ---------------
   -- Set_Errno --
   ---------------

   procedure Set_Errno (Code : Interfaces.C.int) is
      Value : Interfaces.C.int
        with Import => True, Address => Errno_Location;
   begin
      Value := Code;
   end Set_Errno;

   ----------------
   -- Note_Child --
   ----------------

   procedure Note_Child (Process_Id : Integer) is
   begin
      if Process_Id > 0 then
         Pending.Add (Process_Id);
      end if;
   exception
      when others =>
         null;
   end Note_Child;

   -------------------------
   -- Reap_Noted_Children --
   -------------------------

   procedure Reap_Noted_Children is
   begin
      Pending.Reap;
   exception
      when others =>
         null;
   end Reap_Noted_Children;

   --------------------
   -- Read_Directory --
   --------------------

   function Read_Directory (Directory : System.Address) return Boolean is
      use type System.Address;
      Item : System.Address;
   begin
      loop
         Set_Errno (0);
         Item := Readdir (Directory);
         exit when Item = System.Null_Address;
         if not Visit (Item) then
            return True;
         end if;
      end loop;
      return Errno = 0;
   end Read_Directory;

   ------------------------
   -- Saturating_Natural --
   ------------------------

   function Saturating_Natural (Value : Interfaces.Unsigned_64) return Natural is
     (if Value > Interfaces.Unsigned_64 (Natural'Last) then Natural'Last else Natural (Value));

   ----------------------
   -- Saturating_Count --
   ----------------------

   function Saturating_Count (Value : Interfaces.Unsigned_64) return Long_Long_Integer is
     (if Value > Interfaces.Unsigned_64 (Long_Long_Integer'Last) then Long_Long_Integer'Last
      else Long_Long_Integer (Value));

   ---------------------------
   -- Saturating_Byte_Count --
   ---------------------------

   function Saturating_Byte_Count (Blocks, Unit_Size : Interfaces.Unsigned_64) return Long_Long_Integer is
      Block_Count : constant Long_Long_Integer := Saturating_Count (Blocks);
      Unit        : constant Long_Long_Integer := Saturating_Count (Unit_Size);
   begin
      if Block_Count = 0 or else Unit = 0 then
         return 0;
      elsif Block_Count > Long_Long_Integer'Last / Unit then
         return Long_Long_Integer'Last;
      else
         return Block_Count * Unit;
      end if;
   end Saturating_Byte_Count;

end Hostkit.Posix;
