--[[
  Copyright 2016,2019 ARATA Mizuki
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

local os           = require"os_"
local assert       = assert
local string_match = string.match
local table        = table
local table_insert = table.insert
local table_concat = table.concat
local os_execute   = os.execute

local function escape(s: string): string
	local len = #s
	local result = {}
	local t, i = string_match(s, "^([^']*)()") as (string, integer)
	assert(t)
	if t ~= "" then
		table_insert(result, "'")
		table_insert(result, t)
		table_insert(result, "'")
	end
	while i < len do
		t, i = string_match(s, "^('+)()", i) as (string, integer)
		assert(t)
		table_insert(result, '"')
		table_insert(result, t)
		table_insert(result, '"')
		t, i = string_match(s, "^([^']*)()", i) as (string, integer)
		assert(t)
		if t ~= "" then
			table_insert(result, "'")
			table_insert(result, t)
			table_insert(result, "'")
		end
	end
	return table_concat(result, "")
end

local function has_command(name: string): boolean
	local result = os_execute("which " .. escape(name) .. " > /dev/null 2>/dev/null")
	return result == 0
end

return {
	escape = escape,
	has_command = has_command,
}
