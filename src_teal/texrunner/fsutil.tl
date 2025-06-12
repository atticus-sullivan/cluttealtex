-- SPDX-FileCopyrightText: 2016 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local os = require "os_"
local os_remove = os.remove
local filesys = require "lfs"
local pathutil = require "texrunner.pathutil"
local shellutil = require "texrunner.shellutil"
local escape = shellutil.escape

-- Function to construct a copy command string suitable for the current operating system.
-- Escapes paths to prevent shell injection or issues with special characters.
-- On Windows, output is silenced with "> NUL". 
-- TODO: Handle edge cases such as paths beginning with a slash or a hyphen.
local copy_command:function(string,string): string
if os.type == "windows" then
	function copy_command(from: string, to: string): string
		-- Constructs the Windows copy command
		-- TODO: What if `from` begins with a slash?
		return "copy " .. escape(from) .. " " .. escape(to) .. " > NUL"
	end
else
	function copy_command(from: string, to: string): string
		-- Constructs the Unix copy command
		-- TODO: What if `from` begins with a hypen?
		return "cp " .. escape(from) .. " " .. escape(to)
	end
end

-- Function to check if a given path corresponds to a regular file.
-- Returns true if the path is a file, false otherwise.
local function isfile(path: string): boolean
	return filesys.attributes(path, "mode") == "file"
end

-- Function to check if a given path corresponds to a directory.
-- Returns true if the path is a directory, false otherwise.
local function isdir (path: string): boolean
	return filesys.attributes(path, "mode") == "directory"
end

-- Recursively creates a directory and all its parent directories if they do not exist.
-- Returns true if the directory was successfully created or already exists.
-- Returns nil and an error message on failure.
local function mkdir_rec(path: string): boolean|nil, nil|string
	local succ, err = filesys.mkdir(path) -- Attempt to create the directory
	if not succ then
		-- If creation failed, try to create the parent directory first
		succ, err = mkdir_rec(pathutil.parentdir(path))
		if succ then
			-- Retry creating the original directory after its parent exists
			return filesys.mkdir(path)
		end
	end
	return succ, err -- Return success or error details
end

-- Recursively removes a directory and all its contents.
-- Works for both files and directories. If a file is encountered, it is deleted.
-- Returns true if successful, or nil and an error message on failure.
local function remove_rec(path: string): boolean|nil, nil|string
	if isdir(path) then
		-- If the path is a directory, iterate through its contents
		for file in filesys.dir(path) do
			-- Skip special entries "." and ".."
			if file ~= "." and file ~= ".." then
				-- Recursively remove each item in the directory
				local succ, err = remove_rec(pathutil.join(path, file))
				if not succ then
					return succ, err -- Return on first error
				end
			end
		end
		return filesys.rmdir(path) -- Remove the now-empty directory
	else
		-- If the path is a file, remove it
		return os_remove(path)
	end
end

return {
	copy_command = copy_command,
	isfile = isfile,
	isdir = isdir,
	mkdir_rec = mkdir_rec,
	remove_rec = remove_rec,
}
