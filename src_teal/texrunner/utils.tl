-- SPDX-FileCopyrightText: 2016 - 2021 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Standard libraries
local table = table
local os = require"os_"

-- External libraries (included in texlua)
local filesys = require "lfs"
local md5     = require "md5"
-- local kpse = require "kpse"

-- custom modules
local pathutil = require "texrunner.pathutil"
local fsutil   = require "texrunner.fsutil"
local message  = require "texrunner.message"
local safename = require "texrunner.safename"
local engine_t = require "texrunner.tex_engine"
local option_t = require"texrunner.option_type"

-- Record type for storing the environment state
local record Env
	original_wd: string
end

-- Record type defining the module interface
local record Module
	prepend_env: function(var:string, value:string, pathsep:string)
	env_setup: function(options: option_t.Options, original_wd: string): Env
	prepare_output_directory: function(options:option_t.Options, inputfile:string, jobname:string)
	initialize_options: function(options:option_t.Options, engine:engine_t.Engine, inputfile: string): string, string
	construct_tex_options: function(options:option_t.Options, engine:engine_t.Engine): engine_t.Option
	path_in_output_directory: function(ext:string, options:option_t.Options, jobname:string): string
end

-- Generates a unique output directory based on the input file and jobname
local function genOutputDirectory(...: string): string
	-- Combine input arguments into a single message with null character as delimiter
	local message = table.concat({...}, "\0")

	-- Generate a hash to ensure the directory name is unique
	local hash = md5.sumhexa(message)

	-- Determine the system's temporary directory
	local tmpdir = os.getenv("TMPDIR") or os.getenv("TMP") or os.getenv("TEMP")
	if not tmpdir then
		-- Fallback to home directory if no temp directory is defined
		local home = os.getenv("HOME") or os.getenv("USERPROFILE") or error("environment variable 'TMPDIR' not set!")
		tmpdir = pathutil.join(home, ".latex-build-temp")
	end

	-- Append a unique directory name to the temp directory path
	return pathutil.join(tmpdir, 'latex-build-' .. hash)
end

-- Prepends a value to the specified environment variable with the appropriate path separator
local function prepend_env(var:string, value:string, pathsep:string)
	os.setenv(var, value .. pathsep .. (os.getenv(var) or ""))
end

-- Sets up the environment variables and working directory for the TeX workflow
local function env_setup(options: option_t.Options, original_wd: string): Env
	local pathsep = os.type == "windows" and ";" or ":" -- Platform-specific path separator

	if options.change_directory then
		-- Change to the output directory if specified
		assert(filesys.chdir(options.output_directory))
		-- Resolve the absolute path of the output
		options.output = pathutil.abspath(options.output, original_wd)

		-- Add the original working directory to input paths for TeX
		prepend_env("TEXINPUTS", original_wd, pathsep)
		prepend_env("LUAINPUTS", original_wd, pathsep)

		-- after changing the pwd, '.' is always the output_directory (needed for some path generation)
		options.output_directory = "."
	end

	if options.bibtex or options.biber then
		-- If bibliography tools are enabled, ensure paths are configured
		prepend_env("BIBINPUTS", original_wd, pathsep)
		options.output = pathutil.abspath(options.output, original_wd)
	end

	-- Configure the maximum line length for TeX output logs
	if not os.getenv("max_print_line") then
		os.setenv("max_print_line", options.bibtex and "19999" or "65536")
	end
	--[[
	  According to texmf.cnf:
		45 < error_line < 255,
		30 < half_error_line < error_line - 15,
		60 <= max_print_line.
	]]
	return {
		-- Store the original working directory for later restoration
		original_wd = original_wd,
	}
end

-- Prepares the output directory, ensuring it exists and handles the `--fresh` option
local function prepare_output_directory(options:option_t.Options, inputfile:string, jobname:string)
	if not options.output_directory then
		-- Generate a unique output directory based on the input file and jobname
		local inputfile_abs = pathutil.abspath(inputfile)
		options.output_directory = genOutputDirectory(inputfile_abs, jobname, options.engine_executable or options.engine)

		-- Ensure the directory exists or clean it if the `--fresh` option is specified
		if not fsutil.isdir(options.output_directory) then
			-- Create directory recursively
			assert(fsutil.mkdir_rec(options.output_directory))
		elseif options.fresh then
			-- Clean the directory if it already exists
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.info("Cleaning '", options.output_directory, "'...")
			end
			-- Remove contents
			assert(fsutil.remove_rec(options.output_directory))
			-- Recreate directory
			assert(filesys.mkdir(options.output_directory))
		end

	elseif options.fresh then
		message.error("--fresh and --output-directory cannot be used together.")
		os.exit(1)
	end
end

-- Initializes and validates the options for the current workflow
local function initialize_options(options:option_t.Options, engine:engine_t.Engine, inputfile: string): string, string
	-- Determine the jobname
	local jobname_for_output: string
	if not options.jobname then
		-- Default to the sanitized basename of the input file
		local basename = pathutil.basename(pathutil.trimext(inputfile))
		options.jobname = safename.escapejobname(basename)
		jobname_for_output = basename
	else
		jobname_for_output = options.jobname
	end

	local jobname = options.jobname
	-- Validate jobname is not empty
	assert(jobname ~= "", "jobname cannot be empty")

	-- Determine the output file extension
	local output_extension: string
	if options.output_format == "dvi" then
		output_extension = engine.dvi_extension or "dvi"
	else
		output_extension = "pdf"
	end

	-- Generate the output file name if not explicitly specified
	if not options.output then
		options.output = jobname_for_output .. "." .. output_extension
	end
	return jobname, output_extension
end

-- Constructs the options table for the TeX engine
local function construct_tex_options(options:option_t.Options, engine:engine_t.Engine): engine_t.Option
	local tex_options:engine_t.Option = {
		engine_executable = options.engine_executable,
		interaction       = options.interaction,
		file_line_error   = options.file_line_error,
		halt_on_error     = options.halt_on_error,
		synctex           = options.synctex,
		output_directory  = options.output_directory,
		shell_escape      = options.shell_escape,
		shell_restricted  = options.shell_restricted,
		jobname           = options.jobname,
		fmt               = options.fmt,
		extraoptions      = options.tex_extraoptions,
	}
	if options.output_format ~= "pdf" and engine.supports_pdf_generation then
		tex_options.output_format = options.output_format
	end
	return tex_options
end

-- Constructs a file path in the output directory
local function path_in_output_directory(ext:string, options:option_t.Options, jobname:string): string
	return pathutil.join(options.output_directory, jobname .. "." .. ext)
end

-- Define and return the module interface
local _M:Module = {
	prepend_env              = prepend_env,
	env_setup                = env_setup,
	prepare_output_directory = prepare_output_directory,
	initialize_options       = initialize_options,
	construct_tex_options    = construct_tex_options,
	path_in_output_directory = path_in_output_directory,
}

return _M
