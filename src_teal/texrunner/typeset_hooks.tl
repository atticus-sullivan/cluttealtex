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

local os = require"os_"

local option_t = require "texrunner.option_type"

local function includeonly(options:option_t.Options, tex_injection: string): string
	return string.format("%s\\includeonly{%s}", tex_injection or "", options.includeonly)
end

local function ps_minted(options:option_t.Options, tex_injection: string): string
	local outdir = options.output_directory
	if os.type == "windows" then
		outdir = string.gsub(outdir, "\\", "/") -- Use forward slashes
	end

	return string.format("%s\\PassOptionsToPackage{outputdir=%s}{minted}", tex_injection or "", outdir)
end

local function ps_epstopdf(options:option_t.Options, tex_injection: string): string
	local outdir = options.output_directory
	if os.type == "windows" then
		outdir = string.gsub(outdir, "\\", "/") -- Use forward slashes
	end
	if string.sub(outdir, -1, -1) ~= "/" then
		outdir = outdir.."/" -- Must end with a directory separator
	end

	return string.format("%s\\PassOptionsToPackage{outdir=%s}{epstopdf}", tex_injection or "", outdir)
end

return {
	includeonly = includeonly,
	ps_minted   = ps_minted,
	ps_epstopdf = ps_epstopdf,
}
