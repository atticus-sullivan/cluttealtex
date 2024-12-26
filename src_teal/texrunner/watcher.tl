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

local os             = require"os_"
local pathutil       = require "texrunner.pathutil"
local shellutil      = require "texrunner.shellutil"
local options        = require "texrunner.option_type"
local message        = require "texrunner.message"
local reruncheck     = require "texrunner.reruncheck"
local fswatcherlib_t = require"texrunner.fswatcher"

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end


local function gather_input_files_to_watch(max_watches: integer, options: options.Options, filelist: {reruncheck.Filemap_ele}): {string}
	local input_files_to_watch = {}
	for _,fileinfo in ipairs(filelist) do
		if fileinfo.kind == "input" then
			local watch = false
			if options.watch_inc_exc then
				watch = false
				for _,v in ipairs(options.watch_inc_exc) do
					if v.type == "only_path" then
						if string.sub(fileinfo.abspath, 1, #v.param) == v.param then
							watch = true
						end
					elseif v.type == "only_ext" then
						if pathutil.ext(fileinfo.abspath) == v.param then
							watch = true
						end
					elseif v.type == "not_path" then
						if string.sub(fileinfo.abspath, 1, #v.param) == v.param then
							watch = false
						end
					elseif v.type == "not_ext" then
						if pathutil.ext(fileinfo.abspath) == v.param then
							watch = false
						end
					end
				end
			else
				watch = true
			end

			if watch then
				table.insert(input_files_to_watch, fileinfo.abspath)
			end
		end
	end
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

	local do_watch: function({string}):boolean
	local max_watches: integer
	if fswatcherlib then
		max_watches = -1 -- no limit known to me
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using built-in filesystem watcher for Windows")
		end
		do_watch = function(files:{string}): boolean
			local watcher = assert(fswatcherlib.new())
			for _,path in ipairs(files) do
				assert(watcher:add_file(path))
			end
			local result = assert(watcher:next())
			if CLUTTEALTEX_VERBOSITY >= 2 then
				message.info(string.format("%s %s", result.action, result.path))
			end
			watcher:close()
			return true
		end
	elseif (options.watch == "auto" or options.watch == "fswatch") and shellutil.has_command("fswatch") then
		max_watches = -1 -- no limit known to me
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using `fswatch' command")
		end
		do_watch = function(files:{string}): boolean
			local fswatch_command = {"fswatch", "--one-event", "--event=Updated", "--"}
			for _,path in ipairs(files) do
				table.insert(fswatch_command, shellutil.escape(path))
			end
			local fswatch_command_str = table.concat(fswatch_command, " ")
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.exec(fswatch_command_str)
			end
			local fswatch = assert(io.popen(fswatch_command_str, "r"))
			for l in fswatch:lines() do
				for _,path in ipairs(files) do
					if l == path then
						fswatch:close()
						return true
					end
				end
			end
			return false
		end
	elseif (options.watch == "auto" or options.watch == "inotifywait") and shellutil.has_command("inotifywait") then
		max_watches = 1024 -- see https://github.com/inotify-tools/inotify-tools/blob/210b019fb621d32fd6986b512508fc845f6c9fcb/src/common.cpp#L18C20-L18C24
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using `inotifywait' command")
		end
		do_watch = function(files:{string}): boolean
			local inotifywait_command = {"inotifywait", "--event=modify", "--event=attrib", "--format=%w", "--quiet"}
			for _,path in ipairs(files) do
				table.insert(inotifywait_command, shellutil.escape(path))
			end
			local inotifywait_command_str = table.concat(inotifywait_command, " ")
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.exec(inotifywait_command_str)
			end
			local inotifywait = assert(io.popen(inotifywait_command_str, "r"))
			for l in inotifywait:lines() do
				for _,path in ipairs(files) do
					if l == path then
						inotifywait:close()
						return true
					end
				end
			end
			return false
		end
	else
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
	return do_watch, max_watches
end

local record Module
	get_do_watch: function(options: options.Options): ((function(files:{string}): boolean), integer)
	gather_input_files_to_watch: function(max_watches: integer, options: options.Options, filelist: {reruncheck.Filemap_ele}): {string}
end

local _M:Module = {
	get_do_watch = get_do_watch,
	gather_input_files_to_watch = gather_input_files_to_watch,
}

return _M
