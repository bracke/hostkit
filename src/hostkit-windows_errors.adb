with GNAT.OS_Lib;

package body Hostkit.Windows_Errors is

   --  errno.h of the UCRT and of mingw-w64.
   E_Perm          : constant := 1;
   E_No_Ent        : constant := 2;
   E_Io            : constant := 5;
   E_Bad_F         : constant := 9;
   E_No_Mem        : constant := 12;
   E_Acces         : constant := 13;
   E_Busy          : constant := 16;
   E_Exist         : constant := 17;
   E_X_Dev         : constant := 18;
   E_Not_Dir       : constant := 20;
   E_Inval         : constant := 22;
   E_M_File        : constant := 24;
   E_No_Spc        : constant := 28;
   E_Ro_Fs         : constant := 30;
   E_Name_Too_Long : constant := 38;
   E_No_Sys        : constant := 40;
   E_Not_Empty     : constant := 41;
   --  The UCRT's POSIX supplement: ELOOP is 114 there, not Linux's 40.
   E_Loop          : constant := 114;

   function Errno_Of (Code : Interfaces.Unsigned_32) return Integer is
   begin
      case Code is
         when 0 =>                         --  ERROR_SUCCESS
            return 0;
         when 2 | 3 | 15 | 18 | 53 | 67 | 161 | 1921 =>
            --  FILE_NOT_FOUND, PATH_NOT_FOUND, INVALID_DRIVE, NO_MORE_FILES,
            --  BAD_NETPATH, BAD_NET_NAME, BAD_PATHNAME, CANT_RESOLVE_FILENAME:
            --  nothing there, as Hostkit.Fs reads them.
            return E_No_Ent;
         when 4 =>                         --  TOO_MANY_OPEN_FILES
            return E_M_File;
         when 5 | 65 | 82 =>               --  ACCESS_DENIED, NETWORK_ACCESS_DENIED, CANNOT_MAKE
            return E_Acces;
         when 1314 =>                      --  PRIVILEGE_NOT_HELD
            return E_Perm;
         when 6 =>                         --  INVALID_HANDLE
            return E_Bad_F;
         when 8 | 14 =>                    --  NOT_ENOUGH_MEMORY, OUTOFMEMORY
            return E_No_Mem;
         when 16 | 32 | 33 | 142 | 170 | 1224 =>
            --  CURRENT_DIRECTORY (a folder some process stands in),
            --  SHARING_VIOLATION, LOCK_VIOLATION, BUSY_DRIVE, BUSY and
            --  USER_MAPPED_FILE: someone else holds it.
            return E_Busy;
         when 17 =>                        --  NOT_SAME_DEVICE
            return E_X_Dev;
         when 19 =>                        --  WRITE_PROTECT
            return E_Ro_Fs;
         when 23 | 29 | 30 | 31 | 1117 =>  --  CRC, WRITE_FAULT, READ_FAULT, GEN_FAILURE, IO_DEVICE
            return E_Io;
         when 39 | 112 | 1295 =>           --  HANDLE_DISK_FULL, DISK_FULL, DISK_QUOTA_EXCEEDED
            --  Windows has no EDQUOT: a full quota is no room, as a full disk.
            return E_No_Spc;
         when 50 | 1 =>                    --  NOT_SUPPORTED, INVALID_FUNCTION
            return E_No_Sys;
         when 80 | 183 =>                  --  FILE_EXISTS, ALREADY_EXISTS
            return E_Exist;
         when 145 =>                       --  DIR_NOT_EMPTY
            return E_Not_Empty;
         when 206 =>                       --  FILENAME_EXCED_RANGE
            return E_Name_Too_Long;
         when 267 =>                       --  DIRECTORY (the name is no folder)
            return E_Not_Dir;
         when 681 =>                       --  STOPPED_ON_SYMLINK: a link, not followed
            return E_Loop;
         when others =>                    --  INVALID_NAME, INVALID_PARAMETER and the rest
            return E_Inval;
      end case;
   end Errno_Of;

   procedure Set_Errno_From (Code : Interfaces.Unsigned_32) is
      use type Interfaces.Unsigned_32;
   begin
      if Code /= 0 then
         GNAT.OS_Lib.Set_Errno (Errno_Of (Code));
      end if;
   end Set_Errno_From;

end Hostkit.Windows_Errors;
