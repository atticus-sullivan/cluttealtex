-- SPDX-FileCopyrightText: 2016 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local os             = require"os_"
local pathutil       = require "texrunner.pathutil"
local shellutil      = require "texrunner.shellutil"
local options        = require "texrunner.option_type"
local message        = require "texrunner.message"
local fswatcherlib_t = require"texrunner.fswatcher"
local common_t       = require"texrunner.common_types"

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end

-- Helper function to determine whether a file should be watched based on user-specified filters
local function should_watch_file(fileinfo:common_t.Filemap_ele, filters: {options.WatchFilter}): boolean
	if not filters then
		-- If no filters are provided, watch all files by default
		return true
	end
	local watch = false
	-- Loop through all filters and apply the inclusion/exclusion rules
	for _,v in ipairs(filters) do
		if v.type == "inc_path" then
			-- Watch only files with a matching path prefix
			if string.sub(fileinfo.abspath, 1, #v.param) == v.param then
				watch = true
			end
		elseif v.type == "inc_ext" then
			-- Watch only files with a matching extension
			if pathutil.ext(fileinfo.abspath) == v.param then
				watch = true
			end
		elseif v.type == "exc_path" then
			-- Exclude files with a matching path prefix
			if string.sub(fileinfo.abspath, 1, #v.param) == v.param then
				watch = false
			end
		elseif v.type == "exc_ext" then
			-- Exclude files with a matching extension
			if pathutil.ext(fileinfo.abspath) == v.param then
				watch = false
			end
		end
	end
	return watch
end

-- Gather a list of input files to be watched based on filters and maximum allowed watches
local function gather_input_files_to_watch(max_watches: integer, options: options.Options, filelist: {common_t.Filemap_ele}): {string}
	local input_files_to_watch = {}
	-- Iterate over the file list to determine files eligible for watching
	for _,fileinfo in ipairs(filelist) do
		if fileinfo.kind == "input" then
			if should_watch_file(fileinfo, options.watch_filter) then
				table.insert(input_files_to_watch, fileinfo.abspath)
			end
		end
	end

	-- Warn if the number of files exceeds the maximum allowed watches
	if max_watches >= 0 and #input_files_to_watch > max_watches then
		message.warn(string.format(
		"Collected %d input files to watch on. Typically only %d hooks are created." ..
		"The hooks exceeding this limit typically will simply not being installed." ..
		"Consider either to increase this limit (how/if possible depends on the watcher engine) or" ..
		"make use of the --watch-{only,no}-{ext,path} options to restrict the files which CluttealTeX should watch.",
			#input_files_to_watch, max_watches
		))
	end
	return input_files_to_watch
end

-- Create a watcher function for Windows using the built-in library
local function do_watch_windows(lib:fswatcherlib_t.WatcherMod): function({string}): boolean
	return function(files:{string}): boolean
		-- Initialize the watcher
		local watcher = assert(lib.new())
		-- Add all files to the watcher
		for _,path in ipairs(files) do
			assert(watcher:add_file(path))
		end
		-- Wait for a change and return success
		local result = assert(watcher:next())
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info(string.format("%s %s", result.action, result.path))
		end
		-- Clean up the watcher
		watcher:close()
		return true
	end
end

-- Generalized function to watch files using shell commands
local function watch_with_command(command: {string}, files: {string}): boolean
	-- Add all file paths to the shell command
	for _,path in ipairs(files) do
		table.insert(command, shellutil.escape(path))
	end
	-- Build the command string
	local command_str = table.concat(command, " ")
	if CLUTTEALTEX_VERBOSITY >= 1 then
		message.exec(command_str)
	end
	-- Execute the command
	local cmd = assert(io.popen(command_str, "r"))
	-- Process the output and detect changes
	for l in cmd:lines() do
		for _,path in ipairs(files) do
			if l == path then
				-- Clean up on match
				cmd:close()
				return true
			end
		end
	end
	return false
end

-- Create a watcher function for `inotifywait`
local function do_watch_inotifywait(): function({string}): boolean
	return function(files:{string}): boolean
		-- Define the `inotifywait` command and delegate to `watch_with_command`
		local inotifywait_command = {"inotifywait", "--event=modify", "--event=attrib", "--format=%w", "--quiet"}
		return watch_with_command(inotifywait_command, files)
	end
end

-- Create a watcher function for `fswatch`
local function do_watch_fswatch(): function({string}): boolean
	return function(files:{string}): boolean
		-- Define the `fswatch` command and delegate to `watch_with_command`
		local fswatch_command = {"fswatch", "--one-event", "--event=Updated", "--"}
		return watch_with_command(fswatch_command, files)
	end
end

-- Determine the appropriate watcher function based on platform and user options
local function get_do_watch(options: options.Options): ((function(files:{string}): boolean), integer)
	local fswatcherlib:fswatcherlib_t.WatcherMod = nil
	if os.type == "windows" then
		-- Windows: Try built-in filesystem watcher
		local succ, result = pcall(require, "texrunner.fswatcher_windows")
		if not succ and CLUTTEALTEX_VERBOSITY >= 1 then
			message.warn("Failed to load texrunner.fswatcher_windows: " .. result as string)
		end
		fswatcherlib = result
	end

	-- Return the appropriate watcher function and maximum watches
	if fswatcherlib then
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using built-in filesystem watcher for Windows")
		end
		local max_watches = -1 -- no limit known to me
		return do_watch_windows(fswatcherlib), max_watches

	elseif (options.watch == "auto" or options.watch == "fswatch") and shellutil.has_command("fswatch") then
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using `fswatch' command")
		end
		local max_watches = -1 -- no limit known to me
		return do_watch_fswatch(), max_watches

	elseif (options.watch == "auto" or options.watch == "inotifywait") and shellutil.has_command("inotifywait") then
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using `inotifywait' command")
		end
		local max_watches = 1024 -- see https://github.com/inotify-tools/inotify-tools/blob/210b019fb621d32fd6986b512508fc845f6c9fcb/src/common.cpp#L18C20-L18C24
		return do_watch_inotifywait(), max_watches

	else
		-- Handle unsupported configurations and show appropriate error messages
		if options.watch == "auto" then
			message.error("Could not watch files because neither `fswatch' nor `inotifywait' was installed.")
		elseif options.watch == "fswatch" then
			message.error("Could not watch files because your selected engine `fswatch' was not installed.")
		elseif options.watch == "inotifywait" then
			message.error("Could not watch files because your selected engine `inotifywait' was not installed.")
		end
		message.info("See CluttealTeX's manual for details.")
		os.exit(1)
	end
end

local record Module
	get_do_watch: function(options: options.Options): ((function(files:{string}): boolean), integer)
	gather_input_files_to_watch: function(max_watches: integer, options: options.Options, filelist: {common_t.Filemap_ele}): {string}
end

local _M:Module = {
	get_do_watch = get_do_watch,
	gather_input_files_to_watch = gather_input_files_to_watch,
}

return _M
