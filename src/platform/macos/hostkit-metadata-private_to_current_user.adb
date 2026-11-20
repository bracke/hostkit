with Hostkit.Metadata.Private_By_Mode;

separate (Hostkit.Metadata)
function Private_To_Current_User (Path : String) return Boolean is
   use type System.Address;

   --  The extended ACL (acl_t, an opaque pointer), read without following a
   --  final link; ACL_TYPE_EXTENDED, and the walk over its entries
   --  (ACL_FIRST_ENTRY, then ACL_NEXT_ENTRY; acl_get_entry answers 0 for an
   --  entry and -1 past the last). An entry's tag says whether it allows
   --  (ACL_EXTENDED_ALLOW) or denies. None of these is variadic.
   Acl_Type_Extended  : constant C_Int := 16#0000_0100#;
   Acl_First_Entry    : constant C_Int := 0;
   Acl_Next_Entry     : constant C_Int := -1;
   Acl_Extended_Allow : constant C_Int := 1;
   --  ENOENT: the entry has no extended ACL. ENOTSUP and EOPNOTSUPP: its
   --  volume keeps none (FAT, exFAT, an SMB share without them).
   E_No_Entry                : constant := 2;
   E_Not_Supported           : constant := 45;
   E_Operation_Not_Supported : constant := 102;

   function C_Acl_Get_Link (Name : Interfaces.C.Strings.chars_ptr; Kind : C_Int) return System.Address
     with Import, Convention => C, External_Name => "acl_get_link_np";
   function C_Acl_Get_Entry (Acl : System.Address; Entry_Id : C_Int; Item : access System.Address) return C_Int
     with Import, Convention => C, External_Name => "acl_get_entry";
   function C_Acl_Get_Tag_Type (Item : System.Address; Tag : access C_Int) return C_Int
     with Import, Convention => C, External_Name => "acl_get_tag_type";
   function C_Acl_Free (Item : System.Address) return C_Int
     with Import, Convention => C, External_Name => "acl_free";

   --  Whether the entry's extended ACL may grant anyone anything the mode
   --  bits do not: True when it holds an allow entry, and when it cannot be
   --  read or walked at all. An entry without one, or on a volume that keeps
   --  none, answers False; deny entries only take access away.
   function Acl_Grants_Access return Boolean is
      C_Path  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Acl     : constant System.Address := C_Acl_Get_Link (C_Path, Acl_Type_Extended);
      --  Read before anything else may set errno.
      Error   : constant Integer := GNAT.OS_Lib.Errno;
      Item    : aliased System.Address := System.Null_Address;
      Tag     : aliased C_Int := 0;
      Next    : C_Int := Acl_First_Entry;
      Grants  : Boolean := False;
      Ignored : C_Int;
   begin
      Interfaces.C.Strings.Free (C_Path);
      if Acl = System.Null_Address then
         return Error not in E_No_Entry | E_Not_Supported | E_Operation_Not_Supported;
      end if;
      while C_Acl_Get_Entry (Acl, Next, Item'Access) = 0 loop
         Next := Acl_Next_Entry;
         if C_Acl_Get_Tag_Type (Item, Tag'Access) /= 0 or else Tag = Acl_Extended_Allow then
            Grants := True;
            exit;
         end if;
      end loop;
      Ignored := C_Acl_Free (Acl);
      return Grants;
   end Acl_Grants_Access;
begin
   --  The owner, mode and link rule Linux applies (Private_By_Mode), and
   --  no extended ACL that hands anyone more.
   return Hostkit.Metadata.Private_By_Mode (Path)
     and then not Acl_Grants_Access;
exception
   when others =>
      return False;
end Private_To_Current_User;
