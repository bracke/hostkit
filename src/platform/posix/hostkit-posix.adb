with Ada.Containers.Vectors;

with System;

with Hostkit.Posix_Abi;

package body Hostkit.Posix is
   use type Interfaces.C.int;

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

end Hostkit.Posix;
