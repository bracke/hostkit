private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;
with Interfaces;

--  Capture and reproduce the host metadata attached to a directory entry.
--  Every operation is no-follow: a symbolic link's own timestamps and
--  attributes are copied, never those of its target.
package Hostkit.Metadata_Copy is

   type Entry_Times is array (Positive range 1 .. 4) of Interfaces.Integer_64;
   --  Access seconds/nanoseconds, then modification seconds/nanoseconds.
   --  Windows stores its native 100 ns FILETIME value in elements 1 and 3,
   --  with the nanosecond elements zero.

   function Capture_Times
     (Path : String; Times : out Entry_Times) return Boolean;
   function Apply_Times
     (Path : String; Times : Entry_Times) return Boolean;

   type Snapshot is private;
   No_Snapshot : constant Snapshot;

   function Capture (Path : String) return Snapshot;
   function Is_Available (Item : Snapshot) return Boolean;
   function Link_Count (Item : Snapshot) return Interfaces.Unsigned_64;

   procedure Set_Times (Item : in out Snapshot; Times : Entry_Times);

   --  Whether the captured entry is encrypted by the file system (Windows'
   --  EFS), so that its copy must be made encrypted before any byte is
   --  written: Hostkit.Regular_Files.Create_New's Encrypted. False on every
   --  other host.
   --
   --  @param Item Captured entry.
   --  @return True when Item's source carried FILE_ATTRIBUTE_ENCRYPTED.
   function Is_Encrypted (Item : Snapshot) return Boolean;

   --  Apply extended attributes, then the final mode and timestamps.
   --  Preserve_Ownership requests the captured owner where the host has one,
   --  and with it the setuid and setgid bits, which a plain copy drops.
   --
   --  Windows keeps what xattrs hold elsewhere in named data streams -- the
   --  Mark of the Web a browser puts on a download is the Zone.Identifier
   --  stream -- and Apply copies each named stream of the captured source
   --  onto Path, before the times and the read-only attribute are set. As
   --  with xattrs (and cp -a), a destination volume that holds no named
   --  streams (FAT, exFAT) still gets the entry, without them. A directory
   --  whose source was encrypted is marked encrypted, so what is created in
   --  it later is too; an encrypted file was made so by Create_New.
   function Apply
     (Item               : Snapshot;
      Path               : String;
      Preserve_Ownership : Boolean) return Boolean;

private
   type Attribute is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Attribute_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Attribute);

   type Snapshot is record
      Available  : Boolean := False;
      Times      : Entry_Times := [others => 0];
      Links      : Interfaces.Unsigned_64 := 0;
      Mode       : Interfaces.Unsigned_64 := 0;
      Owner      : Interfaces.Unsigned_64 := 0;
      Group      : Interfaces.Unsigned_64 := 0;
      Is_Link    : Boolean := False;
      Attributes : Attribute_Vectors.Vector;
      --  Windows: the captured entry's path and the names of its named data
      --  streams (":name:$DATA"), copied from there by Apply.
      Source     : Ada.Strings.Unbounded.Unbounded_String;
      Streams    : Attribute_Vectors.Vector;
      Encrypted  : Boolean := False;
   end record;

   No_Snapshot : constant Snapshot := (others => <>);

   function Is_Encrypted (Item : Snapshot) return Boolean is (Item.Encrypted);
end Hostkit.Metadata_Copy;
