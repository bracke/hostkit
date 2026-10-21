with Interfaces.C;
with System.Storage_Elements;

--  No parent-death signal here either, but a process handle can be waited
--  on: open the parent, and a thread of our own waits for it and ends the
--  process when it ends. The parent is found by our own process id in a
--  process snapshot. Process ids are reused, so the parent must also have
--  started before we did; one that started later is a stranger that took the
--  id of a parent already gone, and we end at once. A thread of its own, not
--  an Ada task, for the reason the macOS body gives; it calls nothing but the
--  system.
package body Hostkit.Parent_Watch is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.Unsigned_64;
   use type System.Address;

   subtype Dword is Interfaces.C.unsigned_long;
   subtype Handle is System.Address;

   Th32cs_Snapprocess      : constant Dword := 16#0000_0002#;
   Synchronize             : constant Dword := 16#0010_0000#;
   Query_Limited_Info      : constant Dword := 16#0000_1000#;
   Infinite                : constant Dword := 16#FFFF_FFFF#;
   Invalid_Handle_Value    : constant Handle :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);  --  (HANDLE) -1

   type Wide_Name is array (1 .. 260) of Interfaces.C.wchar_t with Convention => C;

   type Process_Entry is record
      Size            : Dword := 0;
      Usage           : Dword := 0;
      Process_Id      : Dword := 0;
      Default_Heap_Id : Interfaces.C.size_t := 0;
      Module_Id       : Dword := 0;
      Threads         : Dword := 0;
      Parent_Id       : Dword := 0;
      Priority_Base   : Interfaces.C.long := 0;
      Flags           : Dword := 0;
      Exe_File        : Wide_Name := [others => Interfaces.C.wide_nul];
   end record
     with Convention => C;

   type File_Time is record
      Low  : Dword := 0;
      High : Dword := 0;
   end record
     with Convention => C;

   function Create_Snapshot (Flags : Dword; Process_Id : Dword) return Handle
     with Import, Convention => Stdcall, External_Name => "CreateToolhelp32Snapshot";
   function Process_First (Snapshot : Handle; Item : access Process_Entry) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "Process32FirstW";
   function Process_Next (Snapshot : Handle; Item : access Process_Entry) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "Process32NextW";
   function Close_Handle (Object : Handle) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";
   function Current_Process_Id return Dword
     with Import, Convention => Stdcall, External_Name => "GetCurrentProcessId";
   function Current_Process return Handle
     with Import, Convention => Stdcall, External_Name => "GetCurrentProcess";
   function Open_Process (Access_Mask : Dword; Inherit : Interfaces.C.int; Process_Id : Dword) return Handle
     with Import, Convention => Stdcall, External_Name => "OpenProcess";
   function Process_Times
     (Process : Handle; Creation, Ended, Kernel, User : access File_Time) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "GetProcessTimes";
   function Wait_For (Object : Handle; Milliseconds : Dword) return Dword
     with Import, Convention => Stdcall, External_Name => "WaitForSingleObject";
   procedure C_Exit (Status : Interfaces.C.int)
     with Import, Convention => C, External_Name => "_exit";

   type Thread_Body is access function (Argument : System.Address) return Dword
     with Convention => Stdcall;

   function Create_Thread
     (Attributes : System.Address; Stack_Size : Interfaces.C.size_t; Start : Thread_Body;
      Argument : System.Address; Flags : Dword; Thread_Id : System.Address) return Handle
     with Import, Convention => Stdcall, External_Name => "CreateThread";

   --  The parent's process id from a snapshot of every process, 0 when ours
   --  is not in it.
   function Parent_Id return Dword is
      Snapshot : constant Handle := Create_Snapshot (Th32cs_Snapprocess, 0);
      Item     : aliased Process_Entry;
      Own      : constant Dword := Current_Process_Id;
      Found    : Dword := 0;
      More     : Interfaces.C.int;
      Ignored  : Interfaces.C.int;
   begin
      if Snapshot = System.Null_Address or else Snapshot = Invalid_Handle_Value then
         return 0;
      end if;
      --  dwSize must be the structure's full size, tail padding included
      --  (568 on x64); its unpadded size makes Process32FirstW refuse it.
      Item.Size := Process_Entry'Object_Size / 8;
      More := Process_First (Snapshot, Item'Access);
      while More /= 0 loop
         if Item.Process_Id = Own then
            Found := Item.Parent_Id;
            exit;
         end if;
         More := Process_Next (Snapshot, Item'Access);
      end loop;
      Ignored := Close_Handle (Snapshot);
      return Found;
   end Parent_Id;

   function Started_At (Process : Handle; Time : out Interfaces.Unsigned_64) return Boolean is
      Creation, Ended, Kernel, User : aliased File_Time;
   begin
      if Process_Times (Process, Creation'Access, Ended'Access, Kernel'Access, User'Access) = 0 then
         Time := 0;
         return False;
      end if;
      Time :=
        Interfaces.Shift_Left (Interfaces.Unsigned_64 (Creation.High), 32)
        or Interfaces.Unsigned_64 (Creation.Low);
      return True;
   end Started_At;

   Parent  : Handle := System.Null_Address;
   Started : Boolean := False;

   function Watch (Argument : System.Address) return Dword
     with Convention => Stdcall;

   function Watch (Argument : System.Address) return Dword is
      pragma Unreferenced (Argument);
      Ignored : Dword;
   begin
      Ignored := Wait_For (Parent, Infinite);
      C_Exit (143);
      return 0;
   end Watch;

   function End_With_Parent return Boolean is
      Parent_Process : constant Dword := (if Started then 0 else Parent_Id);
      Parent_Start   : Interfaces.Unsigned_64;
      Own_Start      : Interfaces.Unsigned_64;
      Thread         : Handle;
      Ignored        : Interfaces.C.int;
   begin
      if Started then
         return True;
      elsif Parent_Process = 0 then
         return False;
      end if;

      Parent := Open_Process (Synchronize or Query_Limited_Info, 0, Parent_Process);
      if Parent = System.Null_Address then
         --  The parent is gone already (or will not let us look): an orphan
         --  from the start has nobody to outlive.
         C_Exit (143);
      end if;

      if not Started_At (Parent, Parent_Start) or else not Started_At (Current_Process, Own_Start) then
         Ignored := Close_Handle (Parent);
         return False;
      elsif Parent_Start > Own_Start then
         --  The id was reused: our parent ended before we asked.
         C_Exit (143);
      end if;

      Thread := Create_Thread (System.Null_Address, 0, Watch'Access, System.Null_Address, 0, System.Null_Address);
      if Thread = System.Null_Address then
         Ignored := Close_Handle (Parent);
         return False;
      end if;
      Ignored := Close_Handle (Thread);
      Started := True;
      return True;
   end End_With_Parent;

end Hostkit.Parent_Watch;
