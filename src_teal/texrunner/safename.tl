-- SPDX-FileCopyrightText: 2019 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local string = string

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end

local engine_t = require"texrunner.tex_engine"

-- Convert unsafe characters in a string to a safe representation.
-- Unsafe characters are replaced with "_xx" (where xx is the hexadecimal ASCII code).
-- Spaces are replaced with a single underscore.
local function dounsafechar(c:string):string
	if c == " " then
		return "_"
	else
		return string.format("_%02x", string.byte(c, 1))
	end
end

-- Escapes job names by replacing unsafe characters with their safe equivalents.
-- Unsafe characters include special symbols and whitespace.
local function escapejobname(name:string): string
	return (string.gsub(name, "[%s\"$%%&'();<>\\^`|]", dounsafechar))
end

-- Escapes special TeX characters that need explicit escaping to be treated as literal text.
-- The characters handled include `\`, `%`, `^`, `{`, `}`, `~`, and `#`.
local function handlespecialchar(s:string): string
	-- Replace special characters with `~\` followed by the character itself
	return (string.gsub(s, "[%\\%%^%{%}%~%#]", "~\\%1"))
end

-- Replaces sequences of two or more spaces with `~` between each space.
-- This ensures that multiple spaces are preserved in the TeX output.
local function handlespaces(s:string): string
	return (string.gsub(s, "  +", function(s:string):string return string.rep(" ", #s, "~") end))
end

-- Wraps non-ASCII characters in a `\detokenize{}` block to ensure they are handled safely by TeX.
-- Non-ASCII characters are identified as those with codes in the range 128-255.
local function handlenonascii(s:string): string
	return (string.gsub(s, "[\x80-\xFF]+", "\\detokenize{%1}"))
end

-- Safely formats and escapes a filename or input string for use in a TeX document.
-- Handles special characters, spaces, and non-ASCII characters, adapting behavior based on the TeX engine.
-- @param name: The name or string to be escaped.
-- @param engine: An `engine_t.Engine` instance specifying the TeX engine being used.
local function safeinput(name:string, engine:engine_t.Engine): string
	-- Step 1: Handle special characters and spaces in the input string
	local escaped = handlespaces(handlespecialchar(name))

	-- Step 2: If the engine is pdftex or pdflatex, handle non-ASCII characters as well
	if engine.name == "pdftex" or engine.name == "pdflatex" then
		escaped = handlenonascii(escaped)
	end

	-- Step 3: Return an appropriate TeX input command
	if name == escaped then
		-- If the escaped name is identical to the input, use the simple \input command
		return string.format("\\input\"%s\"", name)
	else
		-- Otherwise, use a more complex escape sequence to ensure safety
		return string.format("\\begingroup\\escapechar-1\\let~\\string\\edef\\x{\"%s\" }\\expandafter\\endgroup\\expandafter\\input\\x", escaped)
	end
end

local record Module
	escapejobname: function(name:string): string
	safeinput: function(name:string, engine:engine_t.Engine): string

	_internal: Internal

	record Internal
		dounsafechar: function(c:string):string
		handlespecialchar: function(s:string): string
		handlespaces: function(s:string): string
		handlenonascii: function(s:string): string
	end
end

local _M:Module = {
	escapejobname = escapejobname,
	safeinput = safeinput,
}

if CLUTTEALTEX_TEST_ENV then
	_M._internal = {
		dounsafechar = dounsafechar,
		handlespecialchar = handlespecialchar,
		handlespaces = handlespaces,
		handlenonascii = handlenonascii,
	}
end

return _M
