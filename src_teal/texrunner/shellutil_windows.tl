-- SPDX-FileCopyrightText: 2016 - 2019 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local os = require"os_"
local string_gsub = string.gsub
local os_execute = os.execute

local function escape(s: string): string
	return '"' .. string_gsub(string_gsub(s, '(\\*)"', '%1%1\\"'), '(\\+)$', '%1%1') .. '"'
end

local function has_command(name: string): boolean
	local result = os_execute("where " .. escape(name) .. " > NUL 2>&1")
	return result == 0
end

return {
	escape = escape,
	has_command = has_command,
}
