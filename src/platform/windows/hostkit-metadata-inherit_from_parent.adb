separate (Hostkit.Metadata)
function Inherit_From_Parent (Path : String) return Boolean is
   --  UNPROTECTED_DACL_SECURITY_INFORMATION: inherit from the parent.
   Unprotected_Dacl_Information : constant C_DWord := 16#2000_0000#;
   Acl_Header_Size : constant := 8;
   Acl_Revision    : constant := 2;

   --  Item's DACL, through Dacl and the Descriptor holding it (for the
   --  caller to free); False, with errno set, when it cannot be read.
   function Read_Dacl (Item : Wide_String; Dacl, Descriptor : access System.Address) return Boolean is
      Owner, Group, Sacl : aliased System.Address := System.Null_Address;
      Status : constant C_DWord :=
        Get_Named_Security_Info
          (Item'Address, Se_File_Object, Dacl_Information,
           Owner'Access, Group'Access, Dacl, Sacl'Access, Descriptor);
   begin
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
      return Status = Success;
   end Read_Dacl;

   procedure Free (Descriptor : in out System.Address) is
      Freed : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Descriptor /= System.Null_Address then
         Freed := Local_Free (Descriptor);
         Descriptor := System.Null_Address;
      end if;
   end Free;

   --  Item, inside the tree, left with the ACEs it inherits and none set
   --  on it: the stage's, which a file made there takes as its own. The
   --  object alone (Set_Own_Dacl): its folder's ACEs have been handed down
   --  to it already.
   function Drop_Own_Aces (Item : String) return Boolean is
      C_Item     : aliased Wide_String := Wide (Item);
      Dacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;
      Ok         : Boolean;
   begin
      if not Read_Dacl (C_Item, Dacl'Access, Descriptor'Access) then
         return False;
      elsif Dacl = System.Null_Address then
         Free (Descriptor);
         return True;
      end if;
      declare
         Header : constant Acl_Header with Import, Address => Dacl;
         Needed : Natural := Acl_Header_Size;
         Own    : Boolean := False;
      begin
         for Index in 0 .. Natural (Header.Count) - 1 loop
            declare
               Ace : constant Ace_Header with Import, Address => Ace_At (Dacl, Index);
            begin
               if (Ace.Flags and Ace_Inherited) /= 0 then
                  Needed := Needed + Natural (Ace.Size);
               else
                  Own := True;
               end if;
            end;
         end loop;
         --  Nothing of its own to drop; or nothing handed down to keep (a
         --  protected entry the folder's ACEs did not reach), which with
         --  its own ACEs gone could be opened by no one.
         if not Own or else Needed = Acl_Header_Size then
            Free (Descriptor);
            return True;
         end if;
         declare
            --  An ACL is DWORD-aligned.
            Kept : aliased array (1 .. (Needed + 3) / 4) of Interfaces.Unsigned_32 := [others => 0];
         begin
            Ok := Initialize_Acl (Kept'Address, C_DWord (Needed), C_DWord (Header.Revision)) /= 0;
            for Index in 0 .. Natural (Header.Count) - 1 loop
               exit when not Ok;
               declare
                  Found : constant System.Address := Ace_At (Dacl, Index);
                  Ace   : constant Ace_Header with Import, Address => Found;
               begin
                  if (Ace.Flags and Ace_Inherited) /= 0 then
                     Ok := Add_Ace
                       (Kept'Address, C_DWord (Header.Revision), Ace_Append_At_End, Found, C_DWord (Ace.Size)) /= 0;
                  end if;
               end;
            end loop;
            if not Ok then
               Hostkit.Errors.Set_Errno_From_Last_Error;
            end if;
            Free (Descriptor);
            return Ok
              and then Set_Own_Dacl (C_Item'Address, System.Null_Address, Kept'Address, Se_Dacl_Auto_Inherited);
         end;
      end;
   exception
      when others =>
         Free (Descriptor);
         return False;
   end Drop_Own_Aces;

   --  Everything Folder holds, as Drop_Own_Aces leaves it. A link is left
   --  alone: the security calls would reach its target.
   function Drop_Below (Folder : String) return Boolean is
      Entries : Hostkit.Directory_Listing.Entry_Vectors.Vector;
      Ok      : Boolean := True;
   begin
      if not Hostkit.Directory_Listing.List (Folder, Entries) then
         return False;
      end if;
      for Listed of Entries loop
         declare
            Child : constant String := Hostkit.Fs.Join (Folder, Listed.Name);
         begin
            if not Hostkit.Fs.Is_Link (Child) then
               Ok := Drop_Own_Aces (Child) and then Ok;
               if Hostkit.Fs.Kind_Of (Child) = Hostkit.Fs.Directory_Entry then
                  Ok := Drop_Below (Child) and then Ok;
               end if;
            end if;
         end;
      end loop;
      return Ok;
   end Drop_Below;

   C_Path     : aliased Wide_String := Wide (Path);
   Dacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;
   Keeps_Acls : Boolean;
   Empty      : aliased array (1 .. Acl_Header_Size / 4) of Interfaces.Unsigned_32 := [others => 0];
   Status     : C_DWord;
begin
   --  The security calls follow a link: its target is not what moved.
   if Hostkit.Fs.Is_Link (Path) then
      return True;
   elsif not Read_Dacl (C_Path, Dacl'Access, Descriptor'Access) then
      return False;
   end if;
   --  No ACL: a volume that keeps none, or an entry open to all.
   Keeps_Acls := Dacl /= System.Null_Address;
   Free (Descriptor);
   if not Keeps_Acls then
      return True;
   end if;
   --  No ACE of its own, unprotected: Windows gives Path what its parent
   --  hands down and carries that on to everything a folder holds...
   if Initialize_Acl (Empty'Address, Acl_Header_Size, Acl_Revision) = 0 then
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return False;
   end if;
   Status :=
     Set_Named_Security_Info
       (C_Path'Address, Se_File_Object, Dacl_Information or Unprotected_Dacl_Information,
        System.Null_Address, System.Null_Address, Empty'Address, System.Null_Address);
   Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
   if Status /= Success then
      return False;
   end if;
   --  ...where each entry still holds the ACEs the stage gave it.
   return Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Directory_Entry or else Drop_Below (Path);
exception
   when others =>
      Free (Descriptor);
      return False;
end Inherit_From_Parent;
