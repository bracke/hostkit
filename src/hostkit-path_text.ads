with Hostkit.Fs;

--  Reading a path's text the same way wherever it is read: a Windows path
--  met on another host (in a settings file, a drop, a share) still has its
--  separators and its share root. Text only; nothing here touches a disk.
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

end Hostkit.Path_Text;
