separate (Hostkit.Metadata)
function Edited_Dacl
  (Dacl, Owner, Group, Everyone : System.Address;
   Old_Mode, New_Mode           : Natural;
   Runnable                     : Boolean;
   Result                       : out System.Address) return Boolean
is
   type Sid_List is array (1 .. 3) of System.Address;
   type Shift_List is array (1 .. 3) of Positive;
   Sids     : constant Sid_List := [Owner, Group, Everyone];
   Shifts   : constant Shift_List := [64, 8, 1];
   Entries  : aliased Explicit_Access_Array;
   Count    : Natural := 0;
   Replaced : aliased System.Address := System.Null_Address;
   Denied   : aliased System.Address := System.Null_Address;
   Status   : C_DWord;
   Freed    : System.Address;
   pragma Unreferenced (Freed);
begin
   Result := System.Null_Address;
   for Index in Sids'Range loop
      declare
         Old_Bits : constant Natural := (Old_Mode / Shifts (Index)) mod 8;
         New_Bits : constant Natural := Shown ((New_Mode / Shifts (Index)) mod 8, Runnable);
      begin
         --  An owner that is also the primary group is edited as the
         --  owner: the group's bits cannot differ from its own, and
         --  editing them apart would take the owner's ACE with them.
         if Old_Bits /= New_Bits
           and then Sids (Index) /= System.Null_Address
           and then (Index /= 2 or else Owner = System.Null_Address or else Equal_Sid (Group, Owner) = 0)
         then
            Count := Count + 1;
            Build_Trustee_With_Sid (Entries (Count).Trustee'Access, Sids (Index));
            Entries (Count).Permissions :=
              Triplet_To_Rights (New_Bits) or (if Index = 1 then Owner_Only_Rights else 0);
            --  SET_ACCESS replaces the trustee's explicit allow and deny
            --  ACEs. With no bits left it still grants what a stat needs
            --  (Triplet_To_Rights): REVOKE_ACCESS would leave a mode-0
            --  entry no ACE at all, which its owner could then not even
            --  rename or delete.
            Entries (Count).Mode := Set_Access;
            Entries (Count).Inheritance := No_Inheritance;
            Entries (Count).Trustee.Form := Trustee_Is_Sid;
            Entries (Count).Trustee.Kind := Trustee_Is_Unknown;
         end if;
      end;
   end loop;
   if Count = 0 then
      return True;
   end if;
   Status := Set_Entries_In_Acl (C_DWord (Count), Entries (1)'Address, Dacl, Replaced'Access);
   if Status /= Success or else Replaced = System.Null_Address then
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
      return False;
   end if;
   declare
      Left : constant Natural :=
        Without
          (Shown (Triplet_Of (Replaced, Owner, Everyone, Group), Runnable),
           Shown ((New_Mode / 64) mod 8, Runnable));
   begin
      if Left = 0 or else Owner = System.Null_Address then
         Result := Replaced;
         return True;
      end if;
      Entries := [others => <>];
      Build_Trustee_With_Sid (Entries (1).Trustee'Access, Owner);
      Entries (1).Permissions := Rights_To_Deny (Left);
      Entries (1).Mode := Deny_Access;
      Entries (1).Inheritance := No_Inheritance;
      Entries (1).Trustee.Form := Trustee_Is_Sid;
      Entries (1).Trustee.Kind := Trustee_Is_Unknown;
      Status := Set_Entries_In_Acl (1, Entries (1)'Address, Replaced, Denied'Access);
      Freed := Local_Free (Replaced);
      if Status /= Success or else Denied = System.Null_Address then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;
      Result := Denied;
      return True;
   end;
end Edited_Dacl;
