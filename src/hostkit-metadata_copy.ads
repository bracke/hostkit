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

   --  Apply extended attributes, then the final mode and timestamps.
   --  Preserve_Ownership requests the captured owner where the host has one.
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
   end record;

   No_Snapshot : constant Snapshot := (others => <>);
end Hostkit.Metadata_Copy;
