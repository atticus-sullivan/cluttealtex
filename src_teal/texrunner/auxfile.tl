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

local string_match = string.match
local pathutil = require "texrunner.pathutil"
local fsutil = require "texrunner.fsutil"
local message = require "texrunner.message"

local type Report = record
made_new_directory: boolean
end

-- for LaTeX
local function parse_aux_file(auxfile:string, outdir:string, report:Report, seen:{string:boolean}): Report
	report = report or {}
	seen = seen or {}
	seen[auxfile] = true
	for l in io.lines(auxfile) do
		local subauxfile = string_match(l, "\\@input{(.+)}")
		if subauxfile then
			local subauxfile_abs = pathutil.abspath(subauxfile, outdir)
			if fsutil.isfile(subauxfile_abs) then
				parse_aux_file(subauxfile_abs, outdir, report, seen)
			else
				local dir = pathutil.join(outdir, pathutil.dirname(subauxfile))
				if not fsutil.isdir(dir) then
					assert(fsutil.mkdir_rec(dir))
					report.made_new_directory = true
				end
			end
		end
	end
	return report
end

-- \citation, \bibdata, \bibstyle and \@input
local function extract_bibtex_from_aux_file(auxfile:string, outdir:string, biblines:{string}): {string}
	biblines = biblines or {}
	for l in io.lines(auxfile) do
		local name = string_match(l, "\\([%a@]+)")
		if name == "citation" or name == "bibdata" or name == "bibstyle" then
			table.insert(biblines, l)
			if CLUTTEALTEX_VERBOSITY >= 2 then
				message.info("BibTeX line: ", l)
			end
			elseif name == "@input" then
				local subauxfile = string_match(l, "\\@input{(.+)}")
				if subauxfile then
					local subauxfile_abs = pathutil.abspath(subauxfile, outdir)
					if fsutil.isfile(subauxfile_abs) then
						extract_bibtex_from_aux_file(subauxfile_abs, outdir, biblines)
					end
				end
		end
	end
	return biblines
end

return {
	parse_aux_file = parse_aux_file,
	extract_bibtex_from_aux_file = extract_bibtex_from_aux_file,
}
