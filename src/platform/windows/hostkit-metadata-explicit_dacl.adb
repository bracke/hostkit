--  See the declaration in Hostkit.Metadata's body for what the DACL
--  built here holds and in which order.
separate (Hostkit.Metadata)
function Explicit_Dacl
  (Dacl, Owner, Group, Everyone : System.Address;
   Target                       : Natural;
   Runnable                     : Boolean) return Acl_Words
is
   use type Interfaces.Unsigned_32;

   Header : constant Acl_Header with Import, Address => Dacl;
   --  Room for each ACE twice (an ACE handed down is split in two) and
   --  for five of the largest a SID makes, within the most an ACL holds.
   Size   : constant Natural := Natural'Min (8 + 2 * Natural (Header.Size) + 5 * (8 + 68), 65_532);
   Count  : constant Natural := Natural (Header.Count);

   Considered : constant Natural := (if Runnable then 7 else 6);
   Owner_Bits : constant Natural := (Target / 64) mod 8;
   Group_Bits : constant Natural := (Target / 8) mod 8;
   Other_Bits : constant Natural := Target mod 8;
   Has_Owner  : constant Boolean := Owner /= System.Null_Address;
   Has_Group  : constant Boolean :=
     Group /= System.Null_Address and then (not Has_Owner or else Equal_Sid (Group, Owner) = 0);

   type Other_Sid_List is array (1 .. 3) of aliased Sid_Buffer;
   Other_Kinds  : constant array (Other_Sid_List'Range) of C_Int :=
     [Win_World_Sid, Win_Authenticated_User_Sid, Win_Builtin_Users_Sid];
   Other_Sids   : Other_Sid_List := [others => [others => Interfaces.C.nul]];
   Other_Known  : array (Other_Sid_List'Range) of Boolean := [others => False];
   First_Allow  : Natural := 0;

   function Class_Of (Sid : System.Address) return Access_Class is
   begin
      if Has_Owner and then Equal_Sid (Sid, Owner) /= 0 then
         return Owner_Class;
      elsif Has_Group and then Equal_Sid (Sid, Group) /= 0 then
         return Group_Class;
      end if;
      for Index in Other_Sids'Range loop
         if Other_Known (Index) and then Equal_Sid (Sid, Other_Sids (Index) (1)'Address) /= 0 then
            return Other_Class;
         end if;
      end loop;
      return No_Class;
   end Class_Of;

   --  The bits Class keeps.
   function Kept (Class : Access_Class) return Natural is
     (case Class is
         when Owner_Class => Owner_Bits,
         when Group_Class => Group_Bits,
         when Other_Class => Other_Bits,
         when No_Class    => 7);

   --  The bits whoever Class stands for is given: its own, and the
   --  owner's and the group's when it takes them in.
   function Granted (Class : Access_Class) return Natural is
     (case Class is
         when Owner_Class => Owner_Bits,
         when Group_Class => Union (Owner_Bits, Group_Bits),
         when Other_Class => Union (Union (Owner_Bits, Group_Bits), Other_Bits),
         when No_Class    => 0);

   --  The DACL, with a deny of Owner_Deny for the owner and Group_Deny
   --  for the group where not 0.
   function Build (Owner_Deny, Group_Deny : C_DWord) return Acl_Words is
      Words    : Acl_Words (1 .. Size / 4) := [others => 0];
      Revision : constant C_DWord := C_DWord (Header.Revision);
      Built    : Boolean := Initialize_Acl (Words'Address, C_DWord (Size), Revision) /= 0;

      --  Add an ACE of Kind with Flags allowing or denying Mask to Sid.
      procedure Append
        (Kind, Flags : Interfaces.C.unsigned_char;
         Mask        : C_DWord;
         Sid         : System.Address)
      is
         Ace_Size : constant Natural := 8 + Natural (Get_Length_Sid (Sid));
         Ace      : Acl_Words (1 .. (Ace_Size + 3) / 4) := [others => 0];
      begin
         if not Built then
            return;
         end if;
         --  ACE_HEADER, little-endian: type, flags, size; then the mask.
         Ace (1) :=
           Interfaces.Unsigned_32 (Kind) + Interfaces.Unsigned_32 (Flags) * 16#100#
           + Interfaces.Unsigned_32 (Ace_Size) * 16#1_0000#;
         Ace (2) := Interfaces.Unsigned_32 (Mask);
         Built :=
           Copy_Sid (C_DWord (Ace_Size - 8), Ace (3)'Address, Sid) /= 0
           and then Add_Ace (Words'Address, Revision, Ace_Append_At_End, Ace'Address, C_DWord (Ace_Size)) /= 0;
      end Append;

      --  Add the ACE at Source as it is, with Flags.
      procedure Copy (Source : System.Address; Flags : Interfaces.C.unsigned_char) is
         Head     : constant Ace_Header with Import, Address => Source;
         Original : constant Acl_Words (1 .. (Natural (Head.Size) + 3) / 4) with Import, Address => Source;
         Ace      : Acl_Words := Original;
      begin
         if not Built then
            return;
         end if;
         Ace (1) := (Ace (1) and 16#FFFF_00FF#) or Interfaces.Unsigned_32 (Flags) * 16#100#;
         Built := Add_Ace (Words'Address, Revision, Ace_Append_At_End, Ace'Address, C_DWord (Head.Size)) /= 0;
      end Copy;

      --  Add ACE Index of Dacl, made explicit and edited for its class.
      procedure Carry (Index : Natural) is
         Source : constant System.Address := Ace_At (Dacl, Index);
         Head   : constant Ace_Header with Import, Address => Source;
         Raw    : constant Interfaces.Unsigned_32
           with Import, Address => System.Storage_Elements."+" (Source, 4);
         Sid    : constant System.Address := System.Storage_Elements."+" (Source, 8);
         Flags  : constant Interfaces.C.unsigned_char := Head.Flags and not Ace_Inherited;
         Mask   : constant C_DWord := C_DWord (Raw);
         Class  : constant Access_Class :=
           (if Head.Kind = Access_Allowed_Ace or else Head.Kind = Access_Denied_Ace then Class_Of (Sid)
            else No_Class);
      begin
         --  An inherit-only ACE grants nothing here.
         if Class = No_Class or else (Head.Flags and Inherit_Only_Ace) /= 0 then
            Copy (Source, Flags);
            return;
         end if;
         declare
            Edited : constant C_DWord :=
              Specific_Rights (Mask)
              and not Rights_Of_Bits
                (if Head.Kind = Access_Allowed_Ace then Without (Considered, Kept (Class)) else Granted (Class));
         begin
            if Edited = Specific_Rights (Mask) then
               Copy (Source, Flags);
               return;
            end if;
            if Edited /= 0 then
               Append
                 (Head.Kind, Flags and not (Object_Inherit_Ace or Container_Inherit_Ace or No_Propagate_Ace),
                  Edited, Sid);
            end if;
            if (Flags and (Object_Inherit_Ace or Container_Inherit_Ace)) /= 0 then
               Append (Head.Kind, Flags or Inherit_Only_Ace, Mask, Sid);
            end if;
         end;
      end Carry;
   begin
      for Index in 0 .. First_Allow - 1 loop
         Carry (Index);
      end loop;
      if Has_Owner and then Owner_Deny /= 0 then
         Append (Access_Denied_Ace, 0, Owner_Deny, Owner);
      end if;
      --  The owner's ACE even with no bits: it grants what a stat needs.
      if Has_Owner then
         Append (Access_Allowed_Ace, 0, Triplet_To_Rights (Owner_Bits) or Owner_Only_Rights, Owner);
      end if;
      if Has_Group and then Group_Deny /= 0 then
         Append (Access_Denied_Ace, 0, Group_Deny, Group);
      end if;
      if Has_Group and then Group_Bits /= 0 then
         Append (Access_Allowed_Ace, 0, Triplet_To_Rights (Group_Bits), Group);
      end if;
      if Other_Bits /= 0 then
         Append (Access_Allowed_Ace, 0, Triplet_To_Rights (Other_Bits), Everyone);
      end if;
      for Index in First_Allow .. Count - 1 loop
         Carry (Index);
      end loop;
      return (if Built then Words else Words (1 .. 0));
   end Build;
begin
   for Index in Other_Sids'Range loop
      declare
         Length : aliased C_DWord := C_DWord (Sid_Buffer'Length);
      begin
         Other_Known (Index) :=
           Create_Well_Known_Sid
             (Other_Kinds (Index), System.Null_Address, Other_Sids (Index) (1)'Address, Length'Access) /= 0;
      end;
   end loop;
   --  The explicit denies lead a canonical DACL.
   while First_Allow < Count loop
      declare
         Head : constant Ace_Header with Import, Address => Ace_At (Dacl, First_Allow);
      begin
         exit when Head.Kind /= Access_Denied_Ace or else (Head.Flags and Ace_Inherited) /= 0;
      end;
      First_Allow := First_Allow + 1;
   end loop;
   declare
      Plain : constant Acl_Words := Build (0, 0);
   begin
      if Plain'Length = 0 then
         return Plain;
      end if;
      declare
         Owner_Left : constant Natural :=
           (if Has_Owner
            then Without (Shown (Triplet_Of (Plain'Address, Owner, Everyone, Group), Runnable), Owner_Bits)
            else 0);
         Group_Left : constant Natural :=
           (if Has_Group
            then Without (Shown (Triplet_Of (Plain'Address, Group, Everyone), Runnable), Group_Bits)
            else 0);
      begin
         if Owner_Left = 0 and then Group_Left = 0 then
            return Plain;
         end if;
         return Build (Rights_To_Deny (Owner_Left), Rights_To_Deny (Group_Left));
      end;
   end;
end Explicit_Dacl;
