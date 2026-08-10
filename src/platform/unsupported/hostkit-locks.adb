package body Hostkit.Locks is

   --  A host this build does not know. Lock_Unsupported rather than Lock_Error,
   --  and the difference matters: Lock_Error invites a retry, and this will
   --  never succeed. A caller must not read either as "the file is protected".

   function Acquire
     (Path : String;
      Kind : Lock_Kind;
      Wait : Boolean;
      Item : out Lock) return Lock_Outcome
   is
      pragma Unreferenced (Path, Kind, Wait);
   begin
      Item.Handle := -1;
      Item.Held   := False;
      return Lock_Unsupported;
   end Acquire;

   procedure Release (Item : in out Lock) is
   begin
      Item.Handle := -1;
      Item.Held   := False;
   end Release;

   function Is_Held (Item : Lock) return Boolean is
   begin
      return Item.Held;
   end Is_Held;

end Hostkit.Locks;
