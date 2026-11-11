with Hostkit.Fs;

--  Reading a path's text the same way wherever it is read: a Windows path
--  met on another host (in a settings file, a drop, a share) still has its
--  separators and its share root. Text only; nothing here touches a disk.
--
--  Leaf and Parent are what Ada.Directories.Simple_Name and
--  Containing_Directory are for, without their limits: GNAT's Windows runtime
--  refuses a component longer than 256 characters as an invalid name, and
--  reads "\\server\share" as a folder of "\\server".
package Hostkit.Path_Text is

   --  Whether C separates Path's components: '/' everywhere, '\' on Windows
   --  and in a path that starts the Windows way (Fs.Has_Windows_Root).
   --
   --  @param Path The path C is part of.
   --  @param C A character of it.
   --  @return True when C is a separator there.
   function Is_Separator_In (Path : String; C : Character) return Boolean is
     (C = '/' or else C = Hostkit.Fs.Separator
      or else (C = '\' and then Hostkit.Fs.Has_Windows_Root (Path)));

   --  Where the share root of a UNC path ends: "\\server\share\" in
   --  "\\server\share\dir" -- the separator closing the share's name when
   --  there is one, else the name's last character -- separators as
   --  Is_Separator_In reads them.
   --
   --  @param Path A path.
   --  @return That index, or 0 when Path names no share ("\\server\").
   function Share_Root_Last (Path : String) return Natural;

   --  How long Path's root is: the text naming where the path starts rather
   --  than a folder in it. "/" (1) for a path that starts with a separator; a
   --  drive, "C:\" (3), or "C:" (2) when that is all of Path; a share,
   --  "\\server\share", without the separator that may close it; the long and
   --  device forms with what they prefix, "\\?\C:\" (7) and
   --  "\\?\UNC\server\share". A server with no share ("\\server\") is root
   --  throughout: it names no folder. A share is read from two leading
   --  backslashes on any host, and from two slashes on Windows only -- on
   --  POSIX "//usr" is "/usr". Separators as Is_Separator_In reads them.
   --
   --  @param Path A path.
   --  @return The root's length, or 0 for a relative path.
   function Root_Length (Path : String) return Natural;

   --  Path's last component: the trailing separators dropped, and nothing
   --  for a root (Root_Length) or an empty path.
   --
   --  @param Path A path.
   --  @return That name, indexed from 1, or "" when Path is a root or empty.
   function Leaf (Path : String) return String;

   --  Path less its last component and the separators before it: a root
   --  keeps its own ("/", "C:\"), a share is "\\server\share". A root has no
   --  parent, and nor has a relative path of one component.
   --
   --  @param Path A path.
   --  @return The parent, indexed from 1, or "" when there is none.
   function Parent (Path : String) return String;

   --  Path made absolute against Base, from the text alone: a relative Path
   --  is read from Base, then "." components are dropped and ".." takes the
   --  component before it away (at the root it is dropped, as the root's
   --  ".." is the root). Empty components go too, and a trailing separator.
   --  The root is kept as written, and the components are rejoined with the
   --  separator the root ends in, else the first the text has, else '\' for
   --  a Windows path and the host's elsewhere.
   --
   --  Windows paths read the Windows way on any host: "\dir" is on Base's
   --  drive or share, and "C:dir" in Base when Base is on C: and at C:'s root
   --  otherwise -- the text does not say where that drive's current folder
   --  is. A path in the \\?\ or \\.\ form is returned as it is, as Windows
   --  takes "." and ".." there as names.
   --
   --  No link is followed and nothing is asked of a disk: "link/.." is the
   --  folder holding "link", where the host would read the folder holding
   --  its target. GNAT's Normalize_Pathname resolves links by default and
   --  refuses a path past its limit on Windows; a caller that wants the
   --  target asks Fs.Real_Path.
   --
   --  @param Path A path, absolute or relative.
   --  @param Base The folder a relative Path is read from; Fs.Current_Directory
   --    for the process's own. When it is "" too, a relative Path stays
   --    relative, its leading ".." components kept.
   --  @return The path, indexed from 1; "" for an empty Path and Base, "." for
   --    a relative path that comes to nothing.
   function Absolute (Path : String; Base : String) return String;

end Hostkit.Path_Text;
