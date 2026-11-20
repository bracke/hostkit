separate (Hostkit.Metadata)
function Evaluated_Rights (Acl, Sid, Everyone, Member_Of : System.Address) return C_DWord is
   Header      : constant Acl_Header with Import, Address => Acl;
   Granted     : C_DWord := 0;
   Denied      : C_DWord := 0;
   Signed_In   : constant Boolean := Member_Of /= System.Null_Address;
   Kinds       : constant array (1 .. 2) of C_Int := [Win_Authenticated_User_Sid, Win_Builtin_Users_Sid];
   Groups      : array (Kinds'Range) of aliased Sid_Buffer := [others => [others => Interfaces.C.nul]];
   Known       : array (Kinds'Range) of Boolean := [others => False];

   function Applies (Ace_Sid : System.Address) return Boolean is
   begin
      if Equal_Sid (Ace_Sid, Sid) /= 0
        or else (Everyone /= System.Null_Address and then Equal_Sid (Ace_Sid, Everyone) /= 0)
        or else (Signed_In and then Equal_Sid (Ace_Sid, Member_Of) /= 0)
      then
         return True;
      end if;
      for Index in Kinds'Range loop
         if Known (Index) and then Equal_Sid (Ace_Sid, Groups (Index) (1)'Address) /= 0 then
            return True;
         end if;
      end loop;
      return False;
   end Applies;
begin
   if Signed_In then
      for Index in Kinds'Range loop
         declare
            Length : aliased C_DWord := C_DWord (Sid_Buffer'Length);
         begin
            Known (Index) :=
              Create_Well_Known_Sid (Kinds (Index), System.Null_Address, Groups (Index) (1)'Address, Length'Access)
              /= 0;
         end;
      end loop;
   end if;
   for Index in 0 .. Natural (Header.Count) - 1 loop
      declare
         Found : aliased System.Address := System.Null_Address;
      begin
         exit when Get_Ace (Acl, C_DWord (Index), Found'Access) = 0;
         declare
            Head : constant Ace_Header with Import, Address => Found;
            Raw  : constant Interfaces.Unsigned_32
              with Import, Address => System.Storage_Elements."+" (Found, 4);
            Mask : constant C_DWord := Specific_Rights (C_DWord (Raw));
         begin
            if (Head.Kind = Access_Allowed_Ace or else Head.Kind = Access_Denied_Ace)
              and then (Head.Flags and Inherit_Only_Ace) = 0
              and then Applies (System.Storage_Elements."+" (Found, 8))
            then
               if Head.Kind = Access_Allowed_Ace then
                  Granted := Granted or (Mask and not Denied);
               else
                  Denied := Denied or (Mask and not Granted);
               end if;
            end if;
         end;
      end;
   end loop;
   return Granted;
end Evaluated_Rights;
