-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local record os_
	clock: function(): number

	-- date: polymorphic function (with types function(): string and function(enum, number): record (day: integer
	-- hour: integer
	-- isdst: boolean
	-- min: integer
	-- month: integer
	-- sec: integer
	-- wday: integer
	-- yday: integer
	-- year: integer) and function(string, number): string)
	difftime: function(number, number): number
	execute: function(string): integer, string, integer
	exit: function(number | boolean, ?boolean)
	getenv: function(string): string
	remove: function(string): boolean, string
	rename: function(string, string): boolean, string
	setlocale: function(string, string): string
	-- time: function(record (day: integer
	-- hour: integer
	-- isdst: boolean
	-- min: integer
	-- month: integer
	-- sec: integer
	-- wday: integer
	-- yday: integer
	-- year: integer)): integer
	tmpname: function(): string

	selfdir: string
	exec: function(cmdline: string | {string}): nil, string
	spawn: function(cmdline: string | {string}): integer | nil, string | nil
	setenv: function(key: string, value: string | nil)
	env: {string: string}
	gettimeofday: function(): number
	-- times: 
	tmpdir: function(): string | nil
	type: string
	name: string
	uname: {string: any}
end

return os_
