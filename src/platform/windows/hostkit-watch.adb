with Ada.Unchecked_Conversion;

with Interfaces.C.Strings;
with System;

package body Hostkit.Watch is

   use Ada.Strings.Unbounded;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.Strings.chars_ptr;
   use type System.Address;

   --  Windows offers ReadDirectoryChangesW, which is richer but asynchronous and
   --  wants an overlapped I/O or completion-port structure around it. All this
   --  caller needs is "did anything change", so the older change-notification
   --  handle is a better fit: it can be waited on with a zero timeout, which
   --  turns it into a poll the render loop can make every frame.

   Invalid_Handle : constant Interfaces.C.ptrdiff_t := -1;

   --  FILE_NOTIFY_CHANGE_FILE_NAME, _DIR_NAME, _ATTRIBUTES, _SIZE,
   --  _LAST_WRITE: the ways a directory listing can go stale.
   Notify_Mask : constant Interfaces.C.unsigned_long :=
     16#0000_0001# or 16#0000_0002# or 16#0000_0004#
     or 16#0000_0008# or 16#0000_0010#;

   Wait_Object_0 : constant Interfaces.C.unsigned_long := 0;

   function Find_First_Change_Notification
     (Path_Name    : Interfaces.C.Strings.chars_ptr;
      Watch_Subtree : Interfaces.C.int;
      Notify_Filter : Interfaces.C.unsigned_long) return System.Address
     with Import, Convention => Stdcall,
          External_Name => "FindFirstChangeNotificationA";

   function Find_Next_Change_Notification
     (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall,
          External_Name => "FindNextChangeNotification";

   function Find_Close_Change_Notification
     (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall,
          External_Name => "FindCloseChangeNotification";

   function Wait_For_Single_Object
     (Handle       : System.Address;
      Milliseconds : Interfaces.C.unsigned_long)
      return Interfaces.C.unsigned_long
     with Import, Convention => Stdcall,
          External_Name => "WaitForSingleObject";

   function To_Address
     (Value : Interfaces.C.ptrdiff_t) return System.Address;
   function To_Value
     (Address : System.Address) return Interfaces.C.ptrdiff_t;

   function To_Address
     (Value : Interfaces.C.ptrdiff_t) return System.Address
   is
      function Convert is new
        Ada.Unchecked_Conversion (Interfaces.C.ptrdiff_t, System.Address);
   begin
      return Convert (Value);
   end To_Address;

   function To_Value
     (Address : System.Address) return Interfaces.C.ptrdiff_t
   is
      function Convert is new
        Ada.Unchecked_Conversion (System.Address, Interfaces.C.ptrdiff_t);
   begin
      return Convert (Address);
   end To_Value;

   procedure Release (State : in out Watch_State) is
   begin
      if State.Handle /= Invalid_Handle then
         declare
            Ignored : constant Interfaces.C.int :=
              Find_Close_Change_Notification (To_Address (State.Handle));
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end if;

      State.Handle := Invalid_Handle;
      State.Extra := -1;
      State.Path := Null_Unbounded_String;
   end Release;

   procedure Watch_Path (State : in out Watch_State; Path : String) is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.Null_Ptr;
      Handle : System.Address;
   begin
      if Path = "" then
         Release (State);
         return;
      end if;

      if State.Handle /= Invalid_Handle
        and then To_String (State.Path) = Path
      then
         return;
      end if;

      Release (State);

      C_Path := Interfaces.C.Strings.New_String (Path);
      Handle := Find_First_Change_Notification (C_Path, 0, Notify_Mask);
      Interfaces.C.Strings.Free (C_Path);

      --  The call reports failure as INVALID_HANDLE_VALUE, which is -1 rather
      --  than null.
      if Handle = System.Null_Address
        or else To_Value (Handle) = Invalid_Handle
      then
         return;
      end if;

      State.Handle := To_Value (Handle);
      State.Path := To_Unbounded_String (Path);

   exception
      when others =>
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
         Release (State);
   end Watch_Path;

   function Poll (State : in out Watch_State) return Boolean is
      Handle  : System.Address;
      Changed : Boolean := False;
      Status  : Interfaces.C.unsigned_long;
   begin
      if State.Handle = Invalid_Handle then
         return False;
      end if;

      Handle := To_Address (State.Handle);

      --  A zero timeout makes the wait a test: signalled means the directory
      --  changed, and rearming with FindNextChangeNotification resumes watching.
      loop
         Status := Wait_For_Single_Object (Handle, 0);
         exit when Status /= Wait_Object_0;

         Changed := True;
         State.Events := State.Events + 1;

         --  Rearm, or the handle stays signalled and this spins.
         declare
            Ignored : constant Interfaces.C.int :=
              Find_Next_Change_Notification (Handle);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end loop;

      return Changed;

   exception
      when others =>
         Release (State);
         return False;
   end Poll;

   function Is_Active (State : Watch_State) return Boolean is
   begin
      return State.Handle /= Invalid_Handle;
   end Is_Active;

   function Event_Count (State : Watch_State) return Natural is
   begin
      return State.Events;
   end Event_Count;

end Hostkit.Watch;
