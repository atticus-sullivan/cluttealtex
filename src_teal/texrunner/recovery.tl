--[[
  Copyright 2018 ARATA Mizuki
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
local parse_aux_file = require "texrunner.auxfile".parse_aux_file
local pathutil       = require "texrunner.pathutil"
local fsutil         = require "texrunner.fsutil"
local shellutil      = require "texrunner.shellutil"
local message        = require "texrunner.message"
local option_t       = require "texrunner.option_type"

local record Args
	auxfile: string
	execlog: string
	options: option_t.Options
	original_wd: string
end

local function create_missing_directories(args:Args): boolean
	if string.find(args.execlog, "I can't write on file", 1, true) then
		-- There is a possibility that there are some subfiles under subdirectories.
		-- Directories for sub-auxfiles are not created automatically, so we need to provide them.
		local report = parse_aux_file(args.auxfile, args.options.output_directory)
		if report.made_new_directory then
			if CLUTTEX_VERBOSITY >= 1 then
				message.info("Created missing directories.")
			end
			return true
		end
	end
	return false
end

local function run_epstopdf(args:Args): boolean
	local run = false
	if args.options.shell_escape ~= false then -- (possibly restricted) \write18 enabled
		for outfile, infile in string.gmatch(args.execlog, "%(epstopdf%)%s*Command: <r?epstopdf %-%-outfile=([%w%-/]+%.pdf) ([%w%-/]+%.eps)>") do
			local infile_abs = pathutil.abspath(infile, args.original_wd)
			if fsutil.isfile(infile_abs) then -- input file exists
				local outfile_abs = pathutil.abspath(outfile, args.options.output_directory)
				if CLUTTEX_VERBOSITY >= 1 then
					message.info("Running epstopdf on ", infile, ".")
				end
				local outdir = pathutil.dirname(outfile_abs)
				if not fsutil.isdir(outdir) then
					assert(fsutil.mkdir_rec(outdir))
				end
				local command = string.format("epstopdf --outfile=%s %s", shellutil.escape(outfile_abs), shellutil.escape(infile_abs))
				message.exec(command)
				local success = os.execute(command)
				run = run or success
			end
		end
	end
	return run
end

local function check_minted(args:Args): boolean
	return string.find(args.execlog, "Package minted Error: Missing Pygments output; \\inputminted was") ~= nil
end

local function try_recovery(args:Args): boolean
	local recovered = false
	recovered = create_missing_directories(args)
	recovered = run_epstopdf(args) or recovered
	recovered = check_minted(args) or recovered
	return recovered
end

return {
	create_missing_directories = create_missing_directories,
	run_epstopdf = run_epstopdf,
	try_recovery = try_recovery,
}
