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

global CLUTTEALTEX_VERSION: string = "v0.9.9" -- TODO(release)

-- Standard libraries
local io = io
local os = require"os_"

-- External libraries (included in texlua)
-- LuaFileSystem for filesystem operations. (https://lunarmodules.github.io/luafilesystem/manual.html#reference)
local filesys = require "lfs"

-- custom modules
local common_t                     = require "texrunner.common_types"
local handle_cluttealtex_options   = require "texrunner.handleoption".handle_cluttealtex_options
local watcher                      = require"texrunner.watcher"
local get_typesetter               = require"texrunner.typeset".get_typesetter
local utils                        = require"texrunner.utils"

os.setlocale("", "ctype") -- Workaround for recent Universal CRT

-- Parse command-line arguments and initialize options.
local inputfile, engine, options = handle_cluttealtex_options(arg)
-- Initialize jobname and output extension based on user inputs and defaults.
local jobname, output_extension = utils.initialize_options(options, engine, inputfile)

-- Prepare the output directory: create it, clean it, or reuse it as specified in options.
utils.prepare_output_directory(options, inputfile, jobname)

-- Print the output directory path and exit if the `--print-output-directory` option is used.
if options.print_output_directory then
	io.write(options.output_directory, "\n")
	os.exit(0)
end

-- Set up the environment, including working directory and environment variables.
local env = utils.env_setup(options, filesys.currentdir())

-- Construct engine options to pass to the TeX typesetting process.
local tex_options = utils.construct_tex_options(options, engine)

-- Shortcut for path_in_output_directory with some arguments already filled in
local path_in_output_directory = function(x: string): string return utils.path_in_output_directory(x, options, jobname) end
options.outfile = path_in_output_directory(output_extension)

-- Setup LuaTeX initialization script
tex_options.lua_initialization_script = engine:setup_luatex_initialization(tex_options, path_in_output_directory("cluttealtexinit.lua"))

-- handle change_directory properly (needs to be after initscript gen)
if options.change_directory then
	tex_options.output_directory = nil
end

-- Create the function responsible for the main typesetting operation.
local do_typeset = get_typesetter{
	path_in_output_directory = path_in_output_directory,
	recorderfile             = path_in_output_directory("fls"),
	recorderfile2            = path_in_output_directory("cluttealtex-fls"),
	engine                   = engine,
	options                  = options,
	output_extension         = output_extension,
	inputfile                = inputfile,
	original_wd              = env.original_wd,
	tex_options              = tex_options
}

-- Variables to track success status and file lists produced during typesetting.
local success, filelist: boolean, {common_t.Filemap_ele}
local _: any -- Placeholder for unused return values.

if options.watch then
	-- Watch mode: Continuously re-run typesetting when input files change.

	-- Initialize the watcher and determine the maximum number of files to monitor.
	local do_watch, max_watches = watcher.get_do_watch(options)

	-- Perform the initial typesetting run.
	success, _, _, filelist = do_typeset()
	-- Gather the list of input files to monitor for changes.
	local input_files_to_watch = watcher.gather_input_files_to_watch(max_watches, options, filelist)

	-- Watch loop: re-run typesetting whenever watched files are modified.
	while do_watch(input_files_to_watch) do
		success, _, _, filelist = do_typeset()
		if not success then
			-- Handle typesetting errors during watch mode.
			-- currently: keep the same list of files watched and keep watching
		else
			-- Update the list of files to watch based on the latest run.
			input_files_to_watch = watcher.gather_input_files_to_watch(max_watches, options, filelist)
		end
	end
else
	-- Single-run mode: Perform the typesetting operation once and exit.
	success, _, _, _ = do_typeset()
	if not success then
		-- Exit with an error code if typesetting fails.
		os.exit(1)
	end
end
