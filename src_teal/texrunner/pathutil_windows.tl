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
  along with CluttealTeX.  If not, see <http://www.gnu.org/licenses/>.
]]

-- pathutil module

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
    local j = string_find(path, "[\\/]", i + 1)
    if j == nil then
      return string_sub(path, i + 1)
    elseif j == #path then
      return string_sub(path, i + 1, -2)
    end
    i = j
  end
end

local function dirname(path: string): string
  local i = 0
  while true do
    local j = string_find(path, "[\\/]", i + 1)
    if j == nil then
      if i == 0 then
        -- No directory portion
        return "."
      elseif i == 1 then
        -- Root
        return string_sub(path, 1, 1)
      else
        -- Directory portion without trailing slash
        return string_sub(path, 1, i - 1)
      end
    end
    i = j
  end
end

local function parentdir(path: string): string
  local i = 0
  while true do
    local j = string_find(path, "[\\/]", i + 1)
    if j == nil then
      if i == 0 then
        -- No directory portion
        return "."
      elseif i == 1 then
        -- Root
        return string_sub(path, 1, 1)
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

local function trimext(path: string): string
  return (string_gsub(path, "%.[^\\/%.]*$", ""))
end

local function ext(path: string): string
  return string_match(path, "%.([^\\/%.]*)$") or ""
end

local function replaceext(path: string, newext: string): string
  local newpath, n = string_gsub(path, "%.([^\\/%.]*)$", function():string return "." .. newext end)
  if n == 0 then
    return newpath .. "." .. newext
  else
    return newpath
  end
end

local function joinpath2(x: string, y: string): string
  local xd = x
  local last = string_sub(x, -1)
  if last ~= "/" and last ~= "\\" then
    xd = x .. "\\"
  end
  if y == "." then
    return xd
  elseif y == ".." then
    return dirname(x)
  else
    if string_match(y, "^%.[\\/]") then
      return xd .. string_sub(y, 3)
    else
      return xd .. y
    end
  end
end

local function joinpath(a?:string, b?:string, ...: string): string
  local n = select("#", ...)
  if not a then
    -- 0 argument
    return "."
  elseif not b then
    -- 1 argument
    return a
  elseif n == 0 then
    -- 2 arguments
    return joinpath2(a, b)
  else
    -- >= 3 arguments
    return joinpath(joinpath2(a, b), ...)
  end
end

-- https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx
local function isabspath(path: string): boolean
  local init = string_sub(path, 1, 1)
  return init == "\\" or init == "/" or string_match(path, "^%a:[/\\]") ~= nil
end

local function abspath(path: string, cwd?: string): string
  if isabspath(path) then
    -- absolute path
    return path
  else
    -- TODO: relative path with a drive letter is not supported
    cwd = cwd or filesys.currentdir()
    return joinpath2(cwd, path)
  end
end

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
