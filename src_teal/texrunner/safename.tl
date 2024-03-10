--[[
  Copyright 2019 ARATA Mizuki
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

local string = string

local engine_t = require"texrunner.tex_engine"

local function dounsafechar(c:string):string
	if c == " " then
		return "_"
	else
		return string.format("_%02x", c:byte(1))
	end
end

local function escapejobname(name:string): string
	return (string.gsub(name, "[%s\"$%%&'();<>\\^`|]", dounsafechar))
end

local function handlespecialchar(s:string): string
	return (string.gsub(s, "[%\\%%^%{%}%~%#]", "~\\%1"))
end

local function handlespaces(s:string): string
	return (string.gsub(s, "  +", function(s:string):string return string.rep(" ", #s, "~") end))
end

local function handlenonascii(s:string): string
	return (string.gsub(s, "[\x80-\xFF]+", "\\detokenize{%1}"))
end

local function safeinput(name:string, engine:engine_t.Engine): string
	local escaped = handlespaces(handlespecialchar(name))
	if engine.name == "pdftex" or engine.name == "pdflatex" then
		escaped = handlenonascii(escaped)
	end
	if name == escaped then
		return string.format("\\input\"%s\"", name)
	else
		return string.format("\\begingroup\\escapechar-1\\let~\\string\\edef\\x{\"%s\" }\\expandafter\\endgroup\\expandafter\\input\\x", escaped)
	end
end

return {
	escapejobname = escapejobname,
	safeinput = safeinput,
}
