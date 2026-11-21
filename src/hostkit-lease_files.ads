with Ada.Streams;
with Interfaces;

--  Secure, process-held lease files for crash-recovery protocols.
--
--  An opened lease is a regular, singly-linked file, owned by this user on
--  POSIX and not a reparse point on Windows. The pathname is never
--  followed through a symbolic link. The advisory lock lives on the open
--  file description/handle and therefore disappears when the process exits.
package Hostkit.Lease_Files is

   type Lock_Kind is (Shared, Exclusive);
   type Open_Outcome is (Opened, Busy, Refused, Unsupported, Error);

   type Lease is limited private;

   --  Create a new owner-only lease and take a shared lock without waiting.
   --
   --  The lease is never at Path unlocked, so another process cannot lock it
   --  first and take it for an abandoned one. POSIX makes it under a unique
   --  temporary name in the same folder (".hostkit-lease-<pid>-<n>"), locks
   --  it there, and only then gives it Path's name with a no-replace rename
   --  -- or, on a filesystem without one, link and unlink, where for that
   --  moment the file has two names and Open refuses it; any failure removes
   --  the temporary. Windows creates it with a share mode that excludes
   --  writers and deleters from the moment CreateFileW returns.
   --
   --  @return Opened; Refused when Path is already taken (by anything, a
   --  link included) or the new file is not what a lease must be; Busy or
   --  Unsupported when it could not be locked; Error otherwise.
   function Create (Path : String; Item : out Lease) return Open_Outcome;

   --  Open an existing validated lease and lock it without waiting.
   function Open
     (Path     : String;
      Kind     : Lock_Kind;
      Writable : Boolean;
      Item     : out Lease) return Open_Outcome;

   procedure Release (Item : in out Lease);
   function Is_Held (Item : Lease) return Boolean;

   --  Positioned exact I/O on the held lease. Write_At makes the bytes durable
   --  before returning True. Read_At succeeds only when all requested bytes
   --  were read. Size is -1 when the host could not answer.
   function Write_At
     (Item   : Lease;
      Data   : Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean;
   function Read_At
     (Item   : Lease;
      Data   : out Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean;
   function Size (Item : Lease) return Long_Long_Integer;

   --  Cut the held lease (opened writable) back to Length bytes, durably, as
   --  Write_At makes its bytes durable: how a record a failed Write_At left
   --  half-written is taken back off the end, so the next record is not
   --  written after a torn one.
   --
   --  @param Item A held lease, opened writable.
   --  @param Length The size to cut it to; no larger than it is.
   --  @return True when the file is Length bytes long and on the device.
   function Truncate (Item : Lease; Length : Long_Long_Integer) return Boolean;

   --  Stable identity of the held file. High is the upper half of Windows'
   --  128-bit file id and zero on POSIX.
   type Lease_Identity is record
      Available : Boolean := False;
      Volume    : Interfaces.Unsigned_64 := 0;
      Low       : Interfaces.Unsigned_64 := 0;
      High      : Interfaces.Unsigned_64 := 0;
   end record;

   function Identity (Item : Lease) return Lease_Identity;
   function Path_Matches (Item : Lease; Path : String) return Boolean;

   --  Can a file be removed -- or the folder that holds it -- while this
   --  process holds a lease on it?
   --
   --  POSIX unlinks a file whatever is open on it, so a caller may keep its
   --  lease until the file is gone and no other claimer can slip in between.
   --  Windows refuses to delete a file with an open handle that does not
   --  share deletion -- which a lease's does not -- so there the lease has
   --  to be released first, and the caller must accept the gap.
   --
   --  A host Hostkit has no body for answers False.
   --
   --  @return True where a held lease file can be removed.
   function Held_File_Removable return Boolean;

private
   use type Interfaces.Integer_64;
   type Lease is limited record
      Handle : Interfaces.Integer_64 := -1;
      Held   : Boolean := False;
   end record;
end Hostkit.Lease_Files;
