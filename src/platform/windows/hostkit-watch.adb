with Ada.Unchecked_Conversion;

with Hostkit.Win32;
with Hostkit.Windows_Paths;
with System;

package body Hostkit.Watch is

   use Ada.Strings.Unbounded;
   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;

   --  Windows offers ReadDirectoryChangesW, which is richer but asynchronous and
   --  wants an overlapped I/O or completion-port structure around it. All this
   --  caller needs is "did anything change", so the older change-notification
   --  handle is a better fit: it can be waited on with a zero timeout, which
   --  turns it into a poll the render loop can make every frame.

   --  What State.Handle holds when nothing is watched: INVALID_HANDLE_VALUE
   --  as the integer the state keeps.
   Invalid_Handle : constant Interfaces.C.ptrdiff_t := -1;

   --  FILE_NOTIFY_CHANGE_FILE_NAME, _DIR_NAME, _ATTRIBUTES, _SIZE,
   --  _LAST_WRITE: the ways a directory listing can go stale.
   Notify_Mask : constant Interfaces.C.unsigned_long :=
     16#0000_0001# or 16#0000_0002# or 16#0000_0004#
     or 16#0000_0008# or 16#0000_0010#;

   Wait_Object_0 : constant Interfaces.C.unsigned_long := 0;
   Wait_Failed   : constant Interfaces.C.unsigned_long := 16#FFFF_FFFF#;

   --  INVALID_FILE_ATTRIBUTES: what GetFileAttributesW answers for a path that
   --  names nothing -- or a folder deleted while something still holds it open,
   --  which Windows keeps, unreachable, until the last handle closes.
   Invalid_File_Attributes : constant DWORD := 16#FFFF_FFFF#;

   function Find_First_Change_Notification
     (Path_Name    : System.Address;
      Watch_Subtree : Interfaces.C.int;
      Notify_Filter : Interfaces.C.unsigned_long) return System.Address
     with Import, Convention => Stdcall,
          External_Name => "FindFirstChangeNotificationW";

   function Find_Next_Change_Notification
     (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall,
          External_Name => "FindNextChangeNotification";

   function Find_Close_Change_Notification
     (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall,
          External_Name => "FindCloseChangeNotification";

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

   --  Whether Path still names a folder.
   function Is_Still_A_Folder (Path : String) return Boolean;

   function Is_Still_A_Folder (Path : String) return Boolean is
      Wide_Path  : aliased constant Wide_String := Hostkit.Windows_Paths.Native (Path);
      Attributes : constant DWORD := Get_File_Attributes (Wide_Path'Address);
   begin
      return Attributes /= Invalid_File_Attributes
        and then (Attributes and File_Attribute_Directory) /= 0;
   end Is_Still_A_Folder;

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

      --  UTF-16, as the folder may not have an ASCII name.
      declare
         Wide_Path : aliased constant Wide_String :=
           Hostkit.Windows_Paths.Native (Path);
      begin
         Handle := Find_First_Change_Notification (Wide_Path'Address, 0, Notify_Mask);
      end;

      --  The call reports failure as INVALID_HANDLE_VALUE, which is -1 rather
      --  than null.
      if Handle = System.Null_Address
        or else Handle = Invalid_Handle_Value
      then
         return;
      end if;

      State.Handle := To_Value (Handle);
      State.Path := To_Unbounded_String (Path);

   exception
      when others =>
         Release (State);
   end Watch_Path;

   function Poll (State : in out Watch_State) return Boolean is
      Handle  : System.Address;
      Changed : Boolean := False;
      Gone    : Boolean := False;
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

         if Status = Wait_Failed then
            Gone := True;
            exit;
         end if;

         exit when Status /= Wait_Object_0;

         Changed := True;
         State.Events := State.Events + 1;

         --  Rearm, or the handle stays signalled and this spins. A handle that
         --  cannot be rearmed will not be signalled again: its folder is gone.
         if Find_Next_Change_Notification (Handle) = 0 then
            Gone := True;
            exit;
         end if;
      end loop;

      --  The folder itself being deleted or renamed signals the handle like any
      --  other change, and the handle stays usable -- it holds the folder,
      --  deleted but kept until the handle closes -- while the path names
      --  nothing. So after a change, and only then, the path is asked whether
      --  it is still a folder; a watch on one that is gone is released, which
      --  also lets go of the folder, and the next Watch_Path on the same path,
      --  a folder made again there included, arms a fresh one.
      if Gone or else (Changed and then not Is_Still_A_Folder (To_String (State.Path))) then
         Release (State);
         return True;
      end if;

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

   --  FILE_NOTIFY_CHANGE_SIZE and _LAST_WRITE are in the filter, but the
   --  system reports them only once the cache writes the file's data out:
   --  a file written while it stays open can go unreported for as long as
   --  the cache holds it (a CI runner showed exactly that).
   function Sees_File_Writes return Boolean is (False);

end Hostkit.Watch;
