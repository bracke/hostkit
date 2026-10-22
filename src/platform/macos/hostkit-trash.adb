with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Hostkit.Trash is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.unsigned_char;
   use type Interfaces.C.Strings.chars_ptr;
   use type System.Address;

   --  -[NSFileManager trashItemAtURL:resultingItemURL:error:], the documented
   --  way to put something in the Finder's trash. It replaced Carbon's
   --  FSMoveObjectToTrashSync, deprecated since 10.8, which this used before.
   --
   --  Reached through the Objective-C runtime rather than an Objective-C
   --  source, so a crate using hostkit needs no Objective-C compiler. Each
   --  message has an import of objc_msgSend with exactly its own arguments
   --  and result: on Apple silicon objc_msgSend must be called through the
   --  prototype of the method it lands in, never as a variadic function, and
   --  a wrong one does not fail to compile -- it reads the wrong registers.
   --  The macOS CI job trashes a real file, which is what keeps these honest.

   function Objc_Get_Class (Name : Interfaces.C.char_array) return System.Address
     with Import, Convention => C, External_Name => "objc_getClass";

   function Sel_Register_Name (Name : Interfaces.C.char_array) return System.Address
     with Import, Convention => C, External_Name => "sel_registerName";

   --  [NSFileManager defaultManager]
   function Send
     (Receiver : System.Address; Selector : System.Address) return System.Address
     with Import, Convention => C, External_Name => "objc_msgSend";

   --  [NSString stringWithUTF8String:]
   function Send_C_String
     (Receiver : System.Address;
      Selector : System.Address;
      Text     : Interfaces.C.Strings.chars_ptr)
      return System.Address
     with Import, Convention => C, External_Name => "objc_msgSend";

   --  [NSURL fileURLWithPath:]
   function Send_Object
     (Receiver : System.Address;
      Selector : System.Address;
      Object   : System.Address)
      return System.Address
     with Import, Convention => C, External_Name => "objc_msgSend";

   --  [manager trashItemAtURL:resultingItemURL:error:], answering a BOOL --
   --  one byte on both architectures.
   function Send_Trash
     (Receiver  : System.Address;
      Selector  : System.Address;
      Item      : System.Address;
      Resulting : System.Address;
      Error     : System.Address)
      return Interfaces.C.unsigned_char
     with Import, Convention => C, External_Name => "objc_msgSend";

   --  The NSString and NSURL made here are autoreleased; without a pool of
   --  our own, on a thread that has none, they would never be freed.
   function Autorelease_Pool_Push return System.Address
     with Import, Convention => C, External_Name => "objc_autoreleasePoolPush";

   procedure Autorelease_Pool_Pop (Pool : System.Address)
     with Import, Convention => C, External_Name => "objc_autoreleasePoolPop";

   Api : constant String := "NSFileManager.trashItemAtURL";

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
         Api_Name              => To_Unbounded_String (Api),
         Uses_Recycle_Bin      => False,
         Preserves_Metadata    => True,
         Requires_User_Consent => False);
   end Current;

   function Move_To_Trash (Path : String) return Boolean is
      use Interfaces.C;
      C_Path  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Pool    : constant System.Address := Autorelease_Pool_Push;
      Trashed : Boolean := False;
   begin
      declare
         Manager_Class : constant System.Address := Objc_Get_Class (To_C ("NSFileManager"));
         String_Class  : constant System.Address := Objc_Get_Class (To_C ("NSString"));
         URL_Class     : constant System.Address := Objc_Get_Class (To_C ("NSURL"));
      begin
         if Manager_Class /= System.Null_Address
           and then String_Class /= System.Null_Address
           and then URL_Class /= System.Null_Address
         then
            declare
               Text : constant System.Address :=
                 Send_C_String (String_Class, Sel_Register_Name (To_C ("stringWithUTF8String:")), C_Path);
               URL : constant System.Address :=
                 (if Text = System.Null_Address then System.Null_Address
                  else Send_Object (URL_Class, Sel_Register_Name (To_C ("fileURLWithPath:")), Text));
               Manager : constant System.Address :=
                 Send (Manager_Class, Sel_Register_Name (To_C ("defaultManager")));
            begin
               --  A path that is not UTF-8 makes no string, and so no URL.
               if URL /= System.Null_Address and then Manager /= System.Null_Address then
                  Trashed :=
                    Send_Trash
                      (Manager,
                       Sel_Register_Name (To_C ("trashItemAtURL:resultingItemURL:error:")),
                       Item      => URL,
                       Resulting => System.Null_Address,
                       Error     => System.Null_Address) /= 0;
               end if;
            end;
         end if;
      end;

      Autorelease_Pool_Pop (Pool);
      Interfaces.C.Strings.Free (C_Path);
      return Trashed;
   exception
      when others =>
         Autorelease_Pool_Pop (Pool);
         Safe_Free (C_Path);
         return False;
   end Move_To_Trash;

end Hostkit.Trash;
