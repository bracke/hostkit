with Interfaces.C;
with System;
separate (Hostkit.Mounts)
--  The drive letters Windows has, not all 26: probing a missing letter or an
--  empty card reader by path could raise the system's "no disk" dialog or
--  wait on a lost mapped drive. Removable and optical drives are listed only
--  with a medium in them, read with the critical-error dialog off.
function Volume_Places return Volume_Place_List is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.int;

   Sem_Fail_Critical_Errors : constant Interfaces.C.unsigned := 16#0001#;
   Drive_No_Root_Dir        : constant Interfaces.C.unsigned := 1;
   Drive_Removable          : constant Interfaces.C.unsigned := 2;
   Drive_Cdrom              : constant Interfaces.C.unsigned := 5;

   function Get_Logical_Drives return Interfaces.C.unsigned
     with Import => True, Convention => Stdcall, External_Name => "GetLogicalDrives";

   function Get_Drive_Type_W (Root : System.Address) return Interfaces.C.unsigned
     with Import => True, Convention => Stdcall, External_Name => "GetDriveTypeW";

   function Get_Volume_Information_W
     (Root           : System.Address;
      Name           : System.Address;
      Name_Size      : Interfaces.C.unsigned;
      Serial         : System.Address;
      Component_Max  : System.Address;
      Flags          : System.Address;
      System_Name    : System.Address;
      System_Size    : Interfaces.C.unsigned) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetVolumeInformationW";

   function Set_Thread_Error_Mode
     (Mode : Interfaces.C.unsigned; Old_Mode : access Interfaces.C.unsigned) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "SetThreadErrorMode";

   --  The same call, its result unused: putting the old mode back can only
   --  fail by leaving the dialogs off.
   procedure Restore_Thread_Error_Mode (Mode : Interfaces.C.unsigned; Old_Mode : access Interfaces.C.unsigned)
     with Import => True, Convention => Stdcall, External_Name => "SetThreadErrorMode";

   Present  : constant Interfaces.C.unsigned := Get_Logical_Drives;
   Result   : Volume_Place_List (1 .. 26);
   Last     : Natural := 0;
   Previous : aliased Interfaces.C.unsigned := 0;
   Restored : aliased Interfaces.C.unsigned := 0;
   Quiet    : constant Boolean := Set_Thread_Error_Mode (Sem_Fail_Critical_Errors, Previous'Access) /= 0;
begin
   for Drive in Character range 'A' .. 'Z' loop
      declare
         Bit  : constant Natural := Character'Pos (Drive) - Character'Pos ('A');
         Root : aliased Wide_String := Wide_Character'Val (Character'Pos (Drive)) & ":\" & Wide_Character'Val (0);
         Kind : Interfaces.C.unsigned;
      begin
         if (Present and Interfaces.C.unsigned (2 ** Bit)) /= 0 then
            Kind := Get_Drive_Type_W (Root'Address);
            if Kind /= Drive_No_Root_Dir
              and then ((Kind /= Drive_Removable and then Kind /= Drive_Cdrom)
                        or else Get_Volume_Information_W
                          (Root'Address, System.Null_Address, 0, System.Null_Address, System.Null_Address,
                           System.Null_Address, System.Null_Address, 0) /= 0)
            then
               Last := Last + 1;
               Result (Last) := (To_Unbounded_String (Drive & ":\"), Drive_Root);
            end if;
         end if;
      end;
   end loop;
   if Quiet then
      Restore_Thread_Error_Mode (Previous, Restored'Access);
   end if;
   return Result (1 .. Last);
end Volume_Places;
