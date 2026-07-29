with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Hostkit.Trash is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   --  This is Carbon's File Manager: an FSRef is the old opaque file reference,
   --  and FSMoveObjectToTrashSync is the call that moves one to the Finder's
   --  trash. Both have been deprecated since 10.8 in favour of
   --  -[NSFileManager trashItemAtURL:resultingItemURL:error:], which is the
   --  documented way and which this should become.
   --
   --  It is not that yet because reaching NSFileManager from Ada means driving
   --  the Objective-C runtime by hand -- objc_getClass, sel_registerName and
   --  objc_msgSend with the right signature per call -- and none of it can be
   --  written blind: a wrong selector or a mismatched msgSend variant does not
   --  fail to compile, it corrupts the stack at run time on a machine nobody
   --  here has. So the working deprecated call was carried over rather than
   --  replaced with an unverified rewrite. It links against CoreServices; if a
   --  future macOS drops the symbol, the macOS CI runner fails to link, which is
   --  the signal to do the Objective-C work properly.
   type FS_Ref is array (1 .. 80) of Interfaces.C.unsigned_char
     with Convention => C;

   function FSPathMakeRef
     (Path         : Interfaces.C.Strings.chars_ptr;
      Reference    : access FS_Ref;
      Is_Directory : System.Address)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "FSPathMakeRef";

   function FSMoveObjectToTrashSync
     (Source_Reference : access FS_Ref;
      Target_Reference : System.Address;
      Options          : Interfaces.C.unsigned)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "FSMoveObjectToTrashSync";

   procedure Safe_Free (Pointer : in out Interfaces.C.Strings.chars_ptr) is
   begin
      if Pointer /= Interfaces.C.Strings.Null_Ptr then
         begin
            Interfaces.C.Strings.Free (Pointer);
         exception
            when others =>
               null;
         end;
      end if;
   end Safe_Free;

   function Current return Facility is
   begin
      return
        (Available             => True,
         Api_Name              => To_Unbounded_String ("FSMoveObjectToTrashSync"),
         Uses_Recycle_Bin      => False,
         Preserves_Metadata    => True,
         Requires_User_Consent => False);
   end Current;

   function Move_To_Trash (Path : String) return Boolean is
      C_Path    : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Reference : aliased FS_Ref;
      Status    : Interfaces.C.int;
   begin
      Status := FSPathMakeRef (C_Path, Reference'Access, System.Null_Address);

      if Status = 0 then
         Status := FSMoveObjectToTrashSync (Reference'Access, System.Null_Address, 0);
      end if;

      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Move_To_Trash;

end Hostkit.Trash;
