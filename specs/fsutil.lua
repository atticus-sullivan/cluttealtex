-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local lfs = require 'lfs'
local lester = require 'lester'

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

local fsutil = require 'src_lua.texrunner.fsutil'
CLUTTEALTEX_VERBOSITY = 0

describe("fsutil", function()
	local tmp_dir = ""
	local original_dir = ""

	before(function()
		-- Save the current working directory
		original_dir = assert(lfs.currentdir())

		-- Create a unique temporary directory
		tmp_dir = os.tmpname()
		os.remove(tmp_dir) -- Remove the temp file placeholder
		lfs.mkdir(tmp_dir)

		-- Change to the temporary directory
		lfs.chdir(tmp_dir)
	end)

	after(function()
		-- Change back to the original working directory
		lfs.chdir(original_dir)

		-- Cleanup: Remove the temporary directory and its contents
		local function rmdir(path)
			for file in lfs.dir(path) do
				if file ~= "." and file ~= ".." then
					local fullpath = path .. "/" .. file
					local attr = lfs.attributes(fullpath)
					if attr and attr.mode == "directory" then
						rmdir(fullpath)
					else
						os.remove(fullpath)
					end
				end
			end
			lfs.rmdir(path)
		end
		rmdir(tmp_dir)
	end)

	it("should correctly detect files with isfile", function()
		-- Create a test file
		local test_file = "testfile.txt"
		local f = assert(io.open(test_file, "w"))
		f:write("Test content")
		f:close()

		-- Check if isfile detects it correctly
		expect.truthy(fsutil.isfile(test_file))
		expect.falsy(fsutil.isfile("nonexistent.txt"))
	end)

	it("should correctly detect directories with isdir", function()
		-- Create a test directory
		local test_dir = "testdir"
		assert(lfs.mkdir(test_dir))

		-- Check if isdir detects it correctly
		expect.truthy(fsutil.isdir(test_dir))
		expect.falsy(fsutil.isdir("nonexistentdir"))
	end)

	it("should recursively create directories with mkdir_rec", function()
		local nested_dir = "level1/level2/level3"

		-- Ensure the nested directory does not exist
		expect.falsy(fsutil.isdir(nested_dir))

		-- Create the nested directory
		local success, err = fsutil.mkdir_rec(nested_dir)
		expect.truthy(success)
		expect.not_exist(err)

		-- Verify the directory exists
		expect.truthy(fsutil.isdir(nested_dir))
	end)

	it("should recursively remove directories and files with remove_rec", function()
		local test_dir = "removeme"
		local nested_file = test_dir .. "/nestedfile.txt"
		local nested_dir = test_dir .. "/nested_dir"

		-- Setup test directory and files
		assert(lfs.mkdir(test_dir))
		local f = assert(io.open(nested_file, "w"))
		f:write("Nested content")
		f:close()
		assert(lfs.mkdir(nested_dir))

		-- Verify setup
		expect.truthy(fsutil.isdir(test_dir))
		expect.truthy(fsutil.isfile(nested_file))
		expect.truthy(fsutil.isdir(nested_dir))

		-- Remove the directory recursively
		local success, err = fsutil.remove_rec(test_dir)
		expect.truthy(success)
		expect.not_exist(err)

		-- Verify the directory no longer exists
		expect.falsy(fsutil.isdir(test_dir))
	end)

	it("should generate correct copy commands for copy_command", function()
		-- Test Windows copy command
		if os.type == "windows" then
			local cmd = fsutil.copy_command("source.txt", "destination.txt")
			expect.equal(cmd, "copy 'source.txt' 'destination.txt' > NUL")
		else
			-- Test Unix copy command
			local cmd = fsutil.copy_command("source.txt", "destination.txt")
			expect.equal(cmd, "cp 'source.txt' 'destination.txt'")
		end
	end)
end)
