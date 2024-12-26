#!/usr/bin/env texlua
--[[
  Copyright 2016-2021 ARATA Mizuki
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

global CLUTTEALTEX_VERSION: string = "v0.8.0"

-- Standard libraries
local table = table
local io = io
local os = require"os_"

-- External libraries (included in texlua)
local filesys = require "lfs"
local md5     = require "md5"
-- local kpse = require "kpse"

-- custom modules
local pathutil                     = require "texrunner.pathutil"
local fsutil                       = require "texrunner.fsutil"
local reruncheck                   = require "texrunner.reruncheck"
local luatexinit                   = require "texrunner.luatexinit"
local message                      = require "texrunner.message"
local safename                     = require "texrunner.safename"
local handle_cluttealtex_options   = require "texrunner.handleoption".handle_cluttealtex_options
local engine_t                     = require "texrunner.tex_engine"
local watcher                      = require"texrunner.watcher"
local do_typeset                   = require"texrunner.typeset".do_typeset

os.setlocale("", "ctype") -- Workaround for recent Universal CRT

-- arguments: input file name, jobname, etc...
local function genOutputDirectory(...: string): string
	-- The name of the temporary directory is based on the path of input file.
	local message = table.concat({...}, "\0")
	local hash = md5.sumhexa(message)
	local tmpdir = os.getenv("TMPDIR") or os.getenv("TMP") or os.getenv("TEMP")
	if tmpdir == nil then
		local home = os.getenv("HOME") or os.getenv("USERPROFILE") or error("environment variable 'TMPDIR' not set!")
		tmpdir = pathutil.join(home, ".latex-build-temp")
	end
	return pathutil.join(tmpdir, 'latex-build-' .. hash)
end

local inputfile, engine, options = handle_cluttealtex_options(arg)

local jobname_for_output: string
if options.jobname == nil then
	local basename = pathutil.basename(pathutil.trimext(inputfile))
	options.jobname = safename.escapejobname(basename)
	jobname_for_output = basename
else
	jobname_for_output = options.jobname
end
local jobname = options.jobname
assert(jobname ~= "", "jobname cannot be empty")

local output_extension: string
if options.output_format == "dvi" then
	output_extension = engine.dvi_extension or "dvi"
else
	output_extension = "pdf"
end

if options.output == nil then
	options.output = jobname_for_output .. "." .. output_extension
end

-- Prepare output directory
if options.output_directory == nil then
	local inputfile_abs = pathutil.abspath(inputfile)
	options.output_directory = genOutputDirectory(inputfile_abs, jobname, options.engine_executable or options.engine)

	if not fsutil.isdir(options.output_directory) then
		assert(fsutil.mkdir_rec(options.output_directory))

	elseif options.fresh then
		-- The output directory exists and --fresh is given:
		-- Remove all files in the output directory
		if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("Cleaning '", options.output_directory, "'...")
		end
		assert(fsutil.remove_rec(options.output_directory))
		assert(filesys.mkdir(options.output_directory))
	end

elseif options.fresh then
	message.error("--fresh and --output-directory cannot be used together.")
	os.exit(1)
end

-- --print-output-directory
if options.print_output_directory then
	io.write(options.output_directory, "\n")
	os.exit(0)
end

local pathsep = ":"
if os.type == "windows" then
	pathsep = ";"
end

local original_wd = filesys.currentdir()
if options.change_directory then
	local TEXINPUTS = os.getenv("TEXINPUTS") or ""
	local LUAINPUTS = os.getenv("LUAINPUTS") or ""
	assert(filesys.chdir(options.output_directory))
	options.output = pathutil.abspath(options.output, original_wd)
	os.setenv("TEXINPUTS", original_wd .. pathsep .. TEXINPUTS)
	os.setenv("LUAINPUTS", original_wd .. pathsep .. LUAINPUTS)
	-- after changing the pwd, '.' is always the output_directory (needed for some path generation)
	options.output_directory = "."
end
if options.bibtex or options.biber then
	local BIBINPUTS = os.getenv("BIBINPUTS") or ""
	options.output = pathutil.abspath(options.output, original_wd)
	os.setenv("BIBINPUTS", original_wd .. pathsep .. BIBINPUTS)
end

-- Set `max_print_line' environment variable if not already set.
if os.getenv("max_print_line") == nil then
	if options.bibtex then
		os.setenv("max_print_line", "19999")
	else
		os.setenv("max_print_line", "65536")
	end
end
-- TODO: error_line, half_error_line
--[[
  According to texmf.cnf:
	45 < error_line < 255,
	30 < half_error_line < error_line - 15,
	60 <= max_print_line.
]]

local function path_in_output_directory(ext:string): string
	return pathutil.join(options.output_directory, jobname .. "." .. ext)
end

local recorderfile = path_in_output_directory("fls")
local recorderfile2 = path_in_output_directory("cluttealtex-fls")

local tex_options:engine_t.Option = {
	engine_executable = options.engine_executable,
	interaction = options.interaction,
	file_line_error = options.file_line_error,
	halt_on_error = options.halt_on_error,
	synctex = options.synctex,
	output_directory = options.output_directory,
	shell_escape = options.shell_escape,
	shell_restricted = options.shell_restricted,
	jobname = options.jobname,
	fmt = options.fmt,
	extraoptions = options.tex_extraoptions,
}
if options.output_format ~= "pdf" and engine.supports_pdf_generation then
	tex_options.output_format = options.output_format
end

-- Setup LuaTeX initialization script
if engine.is_luatex then
	local initscriptfile = path_in_output_directory("cluttealtexinit.lua")
	luatexinit.create_initialization_script(initscriptfile, tex_options)
	tex_options.lua_initialization_script = initscriptfile
end

-- handle change_directory properly (needs to be after initscript gen)
if options.change_directory then
	tex_options.output_directory = nil
end

if options.watch then
	-- Watch mode
	local do_watch, max_watches = watcher.get_do_watch(options)
	local _, _ = do_typeset{path_in_output_directory=path_in_output_directory, recorderfile=recorderfile, recorderfile2=recorderfile2, engine=engine, options=options, output_extension=output_extension, inputfile=inputfile, original_wd=original_wd, tex_options=tex_options}
	-- TODO: filenames here can be UTF-8 if command_line_encoding=utf-8
	-- TODO(refactor) put parse_recorder_file into do_typeset?
	local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
	if engine.is_luatex and fsutil.isfile(recorderfile2) then
		filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
	end


	local input_files_to_watch = watcher.gather_input_files_to_watch(max_watches, options, filelist)
	while do_watch(input_files_to_watch) do
		local success, _ = do_typeset{path_in_output_directory=path_in_output_directory, recorderfile=recorderfile, recorderfile2=recorderfile2, engine=engine, options=options, output_extension=output_extension, inputfile=inputfile, original_wd=original_wd, tex_options=tex_options}
		if not success then
			-- error
		else
			local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
			if engine.is_luatex and fsutil.isfile(recorderfile2) then
				filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
			end
			input_files_to_watch = watcher.gather_input_files_to_watch(max_watches, options, filelist)
		end
	end
else
	-- Not in watch mode
	local success, _ = do_typeset{path_in_output_directory=path_in_output_directory, recorderfile=recorderfile, recorderfile2=recorderfile2, engine=engine, options=options, output_extension=output_extension, inputfile=inputfile, original_wd=original_wd, tex_options=tex_options}
	if not success then
		os.exit(1)
	end
end
