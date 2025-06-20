-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local record lfs

   enum FileMode
      "file"
      "directory"
      "link"
      "socket"
      "named pipe"
      "char device"
      "block device"
      "other"
   end

   record Attributes
      dev: number
      ino: number
      mode: FileMode
      nlink: number
      uid: number
      gid: number
      rdev: number
      access: number
      modification: number
      change: number
      size: number
      permissions: string
      blocks: number
      blksize: number
   end

   enum OpenFileMode
      "binary"
      "text"
   end

   enum LockMode
      "r"
      "w"
   end

   record Lock
      free: function()
   end

   dir: function(string): function(): string

   chdir: function(string): boolean, string

   lock_dir: function(string, number): Lock, string

   -- returns number on success, really!? this should be fixed in the lfs library
   link: function(string, string, boolean): number, string

   mkdir: function(string): boolean, string

   rmdir: function(string): boolean, string

   setmode: function(string, OpenFileMode): boolean, string

   currentdir: function(): string

   attributes: function(string): Attributes
   attributes: function(string, string): string|number -- |FileMode
   attributes: function(string, Attributes): Attributes

   symlinkattributes: function(string): Attributes
   symlinkattributes: function(string, string): string|number -- |FileMode
   symlinkattributes: function(string, Attributes): Attributes

   touch: function(string, ?number, ?number): boolean, string

   lock: function(FILE, LockMode, number, number): boolean, string
   unlock: function(FILE, number, number): boolean, string

  -- only in luatex
  isfile: function(string): boolean

  -- only in luatex
  isdir: function(string): boolean

end

return lfs
