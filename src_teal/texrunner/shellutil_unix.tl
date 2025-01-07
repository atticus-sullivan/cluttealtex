-- SPDX-FileCopyrightText: 2016 - 2019 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

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
