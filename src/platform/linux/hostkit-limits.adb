with Interfaces.C;

package body Hostkit.Limits is

   use type Interfaces.C.int;
   use type Interfaces.Unsigned_64;

   --  The numbers Linux gives these resources, from <asm-generic/resource.h>.
   --  They are not the numbers macOS gives them, which is why this table is
   --  here and not in the spec: NPROC is 6 here and 7 there, and a consumer
   --  that had copied one set would have asked a Mac about the wrong resource
   --  and been answered without complaint.
   Number : constant array (Resource) of Interfaces.C.int :=
     [Processor_Time => 0,
      File_Size      => 1,
      Data_Size      => 2,
      Stack_Size     => 3,
      Core_Size      => 4,
      Processes      => 6,
      Open_Files     => 7,
      Locked_Memory  => 8,
      Address_Space  => 9];

   --  Linux spells infinity with every bit set, which is Amount'Last -- so the
   --  mapping below is an identity here. It is written out anyway, because it
   --  is not an identity on macOS and a reader comparing the two bodies should
   --  see the same shape in both.
   Host_Infinity : constant Interfaces.Unsigned_64 := 16#FFFF_FFFF_FFFF_FFFF#;

   type Rlimit is record
      Current : Interfaces.Unsigned_64 := 0;
      Maximum : Interfaces.Unsigned_64 := 0;
   end record
     with Convention => C;

   function C_Get (Item : Interfaces.C.int; Value : access Rlimit)
                   return Interfaces.C.int
     with Import, Convention => C, External_Name => "getrlimit";

   function C_Set (Item : Interfaces.C.int; Value : access constant Rlimit)
                   return Interfaces.C.int
     with Import, Convention => C, External_Name => "setrlimit";

   function As_Amount (Value : Interfaces.Unsigned_64) return Amount is
     (if Value = Host_Infinity then Unbounded else Value);

   function As_Host (Value : Amount) return Interfaces.Unsigned_64 is
     (if Value = Unbounded then Host_Infinity else Value);

   function Applies (Item : Resource) return Boolean is
      pragma Unreferenced (Item);
   begin
      --  Linux has all nine.
      return True;
   end Applies;

   function Limit
     (Item  : Resource;
      Which : Bound;
      Value : out Amount) return Boolean
   is
      Held : aliased Rlimit;
   begin
      Value := 0;

      if C_Get (Number (Item), Held'Access) /= 0 then
         return False;
      end if;

      Value :=
        As_Amount (if Which = Soft then Held.Current else Held.Maximum);
      return True;
   end Limit;

   function Set_Limit
     (Item  : Resource;
      Which : Bound;
      Value : Amount) return Boolean
   is
      Held : aliased Rlimit;
   begin
      --  Read first, because the host's call takes both numbers together: a
      --  caller lowering the soft limit did not ask for the hard one to follow
      --  it down, and writing a zero there would be a ceiling nothing could
      --  raise again.
      if C_Get (Number (Item), Held'Access) /= 0 then
         return False;
      end if;

      if Which = Soft then
         Held.Current := As_Host (Value);
      else
         Held.Maximum := As_Host (Value);
      end if;

      return C_Set (Number (Item), Held'Access) = 0;
   end Set_Limit;

end Hostkit.Limits;
