--[[
  Copyright 2018 ARATA Mizuki
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

-- Function to create missing directories based on the auxiliary file analysis.
local function create_missing_directories(args:Args): boolean
	-- Check if the log mentions inability to write a file.
	if string.find(args.execlog, "I can't write on file", 1, true) then
		-- There is a possibility that there are some subfiles under subdirectories.
		-- Directories for sub-auxfiles are not created automatically, so we need to provide them.
		local report = parse_aux_file(args.auxfile, args.options.output_directory)

		-- If new directories were created during parsing, log a message and return true.
		if report.made_new_directory then
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.info("Created missing directories.")
			end
			return true
		end
	end
	return false
end

local record inout
	outfile: string
	infile: string
end

-- Function to parse the execution log and extract epstopdf command pairs.
-- It identifies the infile (EPS) and outfile (PDF) arguments for each invocation.
local function parse_epstopdf_commands(execlog:string): {inout}
	local commands = {}
	-- Pattern matches log entries indicating an epstopdf command with input and output files.
	for outfile, infile in string.gmatch(execlog, "%(epstopdf%)%s*Command: <r?epstopdf %-%-outfile=([%w%-/]+%.pdf) ([%w%-/]+%.eps)>") do
		-- Append the parsed infile-outfile pair to the commands table.
		table.insert(commands, { outfile = outfile, infile = infile })
	end
	return commands
end

-- Function to execute a single epstopdf command for converting an EPS file to a PDF file.
-- returns if epstopdf was run (successfully)
local function run_single_epstopdf(inout:inout, options:option_t.Options, original_wd:string): boolean
	local infile_abs = pathutil.abspath(inout.infile, original_wd)

	-- Check if the input file exists before proceeding.
	if fsutil.isfile(infile_abs) then
		-- Resolve the absolute path of the output file and its directory.
		local outfile_abs = pathutil.abspath(inout.outfile, options.output_directory)
		local outdir = pathutil.dirname(outfile_abs)

		-- Ensure the output directory exists, creating it if necessary.
		if not fsutil.isdir(outdir) then
			assert(fsutil.mkdir_rec(outdir))
		end

		-- Construct and execute the epstopdf command.
		local command = string.format("epstopdf --outfile=%s %s", shellutil.escape(outfile_abs), shellutil.escape(infile_abs))
		message.exec(command)
		-- Execute the command
		local ret = os.execute(command)
		return ret
	end
	return false
end

-- Function to run all epstopdf commands parsed from the execution log.
-- returns if epstopdf run and succeeded
local function run_epstopdf(args:Args): boolean
	-- (possibly restricted) \write18 enabled
	if args.options.shell_escape == false then
		return false
	end

	-- Parse the execution log for epstopdf commands.
	local commands = parse_epstopdf_commands(args.execlog)
	-- Flag to track if any command was successfully executed.
	local run = false

	-- Iterate over each parsed command and execute it.
	for _, cmd in ipairs(commands) do
		local success = run_single_epstopdf(cmd, args.options, args.original_wd)
		-- Iterate over each parsed command and execute it.
		run = run or success
	end
	return run
end

-- Function to check if the log contains a specific error related to the minted package.
local function check_minted(args:Args): boolean
	return string.find(args.execlog, "Package minted Error: Missing Pygments output; \\inputminted was") ~= nil
end

-- Function to attempt recovery by invoking multiple corrective actions in sequence.
local function try_recovery(args:Args): boolean
	-- Flag to track if any recovery action succeeded.
	local recovered = false

	-- Attempt to create missing directories.
	recovered = create_missing_directories(args)

	-- Attempt to run epstopdf commands, or update the recovered flag if any succeeded.
	recovered = run_epstopdf(args) or recovered

	-- Check for minted errors and update the recovered flag if found.
	recovered = check_minted(args) or recovered

	return recovered
end

return {
	create_missing_directories = create_missing_directories,
	run_epstopdf = run_epstopdf,
	try_recovery = try_recovery,
}
