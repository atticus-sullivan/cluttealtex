-- SPDX-FileCopyrightText: 2016 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local string_match = string.match
local pathutil = require "texrunner.pathutil"
local fsutil = require "texrunner.fsutil"
local message = require "texrunner.message"

local type Report = record
	made_new_directory: boolean -- Indicates whether a new directory was created during the process.
end

-- Function to parse a LaTeX .aux file and process `\@input` directives.
-- Recursively processes included .aux files and ensures directory structure exists for missing files.
-- @param auxfile (string) - Path to the .aux file being parsed.
-- @param outdir (string) - Output directory for resolving relative paths.
-- @param report (Report|nil) - A report object for tracking directory creation (optional).
-- @param seen (table|nil) - A table tracking already-seen .aux files to prevent infinite recursion (optional).
-- @return (Report) - The report object, with updated information.
local function parse_aux_file(auxfile:string, outdir:string, report?:Report, seen?:{string:boolean}): Report
	-- Initialize the report and seen files tracking if not provided.
	report = report or {}
	seen = seen or {}

	-- skip if the auxfile was already seen
	if seen[auxfile] then
		return
	end

	-- Mark the current auxfile as seen to avoid infinite loops.
	seen[auxfile] = true

	-- Iterate over each line in the .aux file.
	for l in io.lines(auxfile) do
		-- Look for `\@input{filename}` directives in the line.
		local subauxfile = string_match(l, "\\@input{(.+)}")
		if subauxfile then
			-- Resolve the absolute path of the included file.
			local subauxfile_abs = pathutil.abspath(subauxfile, outdir)

			-- Check if the included file exists.
			if fsutil.isfile(subauxfile_abs) then

				-- If the file exists and hasn't been processed, recursively parse it.
				parse_aux_file(subauxfile_abs, outdir, report, seen)
			else
				-- If the file doesn't exist, ensure the directory structure exists.
				local dir = pathutil.join(outdir, pathutil.dirname(subauxfile))
				if not fsutil.isdir(dir) then
					-- Create the directory if it doesn't exist and update the report.
					assert(fsutil.mkdir_rec(dir))
					report.made_new_directory = true
				end
			end
		end
	end
	return report
end

-- Function to extract BibTeX-related lines from a LaTeX .aux file.
-- Supports directives like `\citation`, `\bibdata`, `\bibstyle`, and `\@input`.
-- @param auxfile (string) - Path to the .aux file being processed.
-- @param outdir (string) - Output directory for resolving relative paths.
-- @param biblines (table|nil) - A list of BibTeX-related lines (optional).
-- @param seen (table|nil) - A table tracking already-seen .aux files to prevent infinite recursion (optional).
-- @return (table) - A list of BibTeX-related lines extracted from the .aux file and its dependencies.
local function extract_bibtex_from_aux_file(auxfile:string, outdir:string, biblines?:{string}, seen?:{string:boolean}): {string}
	-- Initialize the list of BibTeX lines and seen files tracking if not provided.
	biblines = biblines or {}
	seen = seen or {}

	-- skip if the auxfile was already seen
	if seen[auxfile] then
		return
	end

	-- Mark the current auxfile as seen to avoid infinite loops.
	seen[auxfile] = true

	 -- Iterate over each line in the .aux file.
	for l in io.lines(auxfile) do
		-- Match the first word in the line that corresponds to a LaTeX directive.
		local name = string_match(l, "\\([%a@]+)")
		if name == "citation" or name == "bibdata" or name == "bibstyle" then
			-- If the line contains a BibTeX directive, add it to the list.
			table.insert(biblines, l)
			if CLUTTEALTEX_VERBOSITY >= 2 then
				message.info("BibTeX line: ", l)
			end
		elseif name == "@input" then
			-- Handle `\@input{filename}` directives by resolving and processing the included file.
			local subauxfile = string_match(l, "\\@input{(.+)}")
			if subauxfile then
				-- Resolve the absolute path of the included file.
				local subauxfile_abs = pathutil.abspath(subauxfile, outdir)

				-- Recursively process the included file if it exists.
				if fsutil.isfile(subauxfile_abs) then
					extract_bibtex_from_aux_file(subauxfile_abs, outdir, biblines, seen)
				end
			end
		end
	end
	return biblines
end

-- Return the module functions.
return {
	parse_aux_file = parse_aux_file,
	extract_bibtex_from_aux_file = extract_bibtex_from_aux_file,
}
