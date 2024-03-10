--[[
  Copyright 2016,2019 ARATA Mizuki
  Copyright 2024 Lukas Heindl

  This file is part of ClutTeX_teal.

  ClutTeX_teal is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  ClutTeX_teal is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with ClutTeX_teal.  If not, see <http://www.gnu.org/licenses/>.
]]

local string_gsub = string.gsub
local os_execute = os.execute

local function escape(s: string): string
  return '"' .. string_gsub(string_gsub(s, '(\\*)"', '%1%1\\"'), '(\\+)$', '%1%1') .. '"'
end

-- TEST CODE
assert(escape([[Hello world!]]) == [["Hello world!"]])
assert(escape([[Hello" world!]]) == [["Hello\" world!"]])
assert(escape([[Hello\" world!"]]) == [["Hello\\\" world!\""]])
-- END TEST CODE

local function has_command(name: string): boolean
  local result = os_execute("where " .. escape(name) .. " > NUL 2>&1")
  return result == true
end

return {
  escape = escape,
  has_command = has_command,
}
