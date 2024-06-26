--[[
  Copyright 2016 ARATA Mizuki
  Copyright 2024 Lukas Heindl

  This file is part of CluttealTeX.

  CluttealTeX is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  CluttealTeX is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with CluttealTeX. If not, see <http://www.gnu.org/licenses/>.
]]

-- pathutil module for *nix

local assert = assert
local select = select
local string = string
local string_find = string.find
local string_sub = string.sub
local string_match = string.match
local string_gsub = string.gsub
local filesys = require "lfs"

local function basename(path: string): string
  local i = 0
  while true do
    local j = string_find(path, "/", i + 1, true)
    if j == nil then
      return string_sub(path, i + 1)
    elseif j == #path then
      return string_sub(path, i + 1, -2)
    end
    i = j
  end
end

-- TEST CODE
assert(basename("/path/to/file") == "file")
assert(basename("/path/to/directory/") == "directory")
assert(basename("/file") == "file")
assert(basename("file") == "file")
-- END TEST CODE

local function dirname(path: string): string
  local i = 0
  while true do
    local j = string_find(path, "/", i + 1, true)
    if j == nil then
      if i == 0 then
        -- No directory portion
        return "."
      elseif i == 1 then
        -- Root
        return "/"
      else
        -- Directory portion without trailing slash
        return string_sub(path, 1, i - 1)
      end
    end
    i = j
  end
end

-- TEST CODE
assert(dirname("/path/to/file") == "/path/to")
assert(dirname("/path/to/directory/") == "/path/to/directory")
assert(dirname("/file") == "/")
assert(dirname("file") == ".")
-- END TEST CODE

local function parentdir(path: string): string
  local i = 0
  while true do
    local j = string_find(path, "/", i + 1, true)
    if j == nil then
      if i == 0 then
        -- No directory portion
        return "."
      elseif i == 1 then
        -- Root
        return "/"
      else
        -- Directory portion without trailing slash
        return string_sub(path, 1, i - 1)
      end
    elseif j == #path then
      -- Directory portion without trailing slash
      return string_sub(path, 1, i - 1)
    end
    i = j
  end
end

-- TEST CODE
assert(parentdir("/path/to/file") == "/path/to")
assert(parentdir("/path/to/directory/") == "/path/to")
assert(parentdir("/file") == "/")
assert(parentdir("file") == ".")
-- END TEST CODE

local function trimext(path: string): string
  return (string_gsub(path, "%.[^/%.]*$", ""))
end

-- TEST CODE
assert(trimext("/path/to/file.ext") == "/path/to/file")
assert(trimext("/path/t.o/file") == "/path/t.o/file")
assert(trimext("file.ext") == "file")
assert(trimext("file.e.xt") == "file.e")
assert(trimext("file.ext.") == "file.ext")
assert(trimext("file") == "file")
-- END TEST CODE

local function ext(path: string): string
  return string_match(path, "%.([^/%.]*)$") or ""
end

-- TEST CODE
assert(ext("/path/to/file.ext") == "ext")
assert(ext("/path/t.o/file") == "")
assert(ext("file.ext") == "ext")
assert(ext("file.e.xt") == "xt")
assert(ext("file.ext.") == "")
assert(ext("file") == "")
-- END TEST CODE

local function replaceext(path: string, newext: string): string
  local newpath, n = string_gsub(path, "%.([^/%.]*)$", function():string return "." .. newext end)
  if n == 0 then
    return newpath .. "." .. newext
  else
    return newpath
  end
end

-- TEST CODE
assert(replaceext("/path/to/file.ext", "tor") == "/path/to/file.tor")
assert(replaceext("/path/t.o/file", "tor") == "/path/t.o/file.tor")
assert(replaceext("file.ext", "tor") == "file.tor")
assert(replaceext("file.e.xt", "tor") == "file.e.tor")
assert(replaceext("file.ext.", "tor") == "file.ext.tor")
assert(replaceext("file", "tor") == "file.tor")
-- END TEST CODE

local function joinpath2(x: string, y: string): string
  local xd = x
  if string_sub(x, -1) ~= "/" then
    xd = x .. "/"
  end
  if y == "." then
    return xd
  elseif y == ".." then
    return dirname(x)
  else
    if string_sub(y, 1, 2) == "./" then
      return xd .. string_sub(y, 3)
    else
      return xd .. y
    end
  end
end

local function joinpath(...: string): string
  local n = select("#", ...)
  if n == 2 then
    return joinpath2(...)
  elseif n == 0 then
    return "."
  elseif n == 1 then
    return ...
  else
	-- n is >= 3
    return joinpath(joinpath2(...), select(3, ...))
  end
end

-- TEST CODE
assert(joinpath("/path/", "to", "somewhere") == "/path/to/somewhere")
assert(joinpath("/path/", "to", "somewhere", "..") == "/path/to")
assert(joinpath("/path/", "to", "somewhere", "..", "elsewhere") == "/path/to/elsewhere")
assert(joinpath("/path/", "to", "./somewhere.txt") == "/path/to/somewhere.txt")
-- END TEST CODE

local function abspath(path: string, cwd: string): string
  if string_sub(path, 1, 1) == "/" then
    -- absolute path
    return path
  else
    cwd = cwd or filesys.currentdir()
    return joinpath2(cwd, path)
  end
end

-- TEST CODE
assert(abspath("world.txt", "/hello") == "/hello/world.txt")
assert(abspath("/world.txt", "/hello") == "/world.txt")
-- END TEST CODE

return {
  basename = basename,
  dirname = dirname,
  parentdir = parentdir,
  trimext = trimext,
  ext = ext,
  replaceext = replaceext,
  join = joinpath,
  abspath = abspath,
}
