local lfs = require 'lfs'
local lester = require 'lester'

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local reruncheck = require 'src_lua.texrunner.reruncheck'
local pathutil = require 'src_lua.texrunner.pathutil'

-- Test cases
describe("reruncheck", function()

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

	-- Tests for md5sum_file
	describe("md5sum", function()
		it("md5sum_file should calculate correct MD5 checksum", function()
			local test_file = "test.txt"
			local content = "sample text"
			local file = io.open(test_file, "w")
			assert(file)
			file:write(content)
			file:close()

			local result = reruncheck._internal.md5sum_file(test_file)
			expect.equal(result, "\x70\xEE\x17\x38\xB6\xB2\x1E\x2C\x8A\x43\xF3\xA5\xAB\x0E\xEE\x71")
		end)
	end)

	-- Tests for binarytohex
	describe("md5sum", function()
		it("binarytohex should convert binary string to hex", function()
			local binary = "\255\254"
			local result = reruncheck._internal.binarytohex(binary)
			expect.equal(result, "fffe")
		end)
	end)

	-- Tests for get_file_attributes
	describe("get_file_attributes", function()
		it("get_file_attributes should return correct attributes", function()
			local test_file = "test_attributes.txt"
			local content = "sample text"
			local file = io.open(test_file, "w")
			assert(file)
			file:write(content)
			file:close()
			lfs.touch(test_file, 42, 1337)

			local result = reruncheck._internal.get_file_attributes(test_file, true, true)
			expect.equal(result.mtime, 1337)
			expect.equal(result.size, 11)
		end)
	end)

	-- Tests for get_output_file_kind
	describe("get_output_file_kind", function()
		it("get_output_file_kind should return correct kind", function()
			local result = reruncheck._internal.get_output_file_kind("out", {})
			expect.equal(result, "auxiliary")
		end)
	end)

	-- Tests for get_input_file_kind
	describe("get_input_file_kind", function()
		it("get_input_file_kind should return correct kind", function()
			local result = reruncheck._internal.get_input_file_kind("bbl", {})
			expect.equal(result, "auxiliary")
		end)
	end)

	-- Tests for parse_recorder_line
	describe("parse_recorder_line", function()
		it("parse_recorder_line should process line correctly", function()
			local filelist = {}
			local filemap = {}
			io.open("test.tex", "w"):close()
			reruncheck._internal.parse_recorder_line("INPUT test.tex", {}, filelist, filemap)
			local abspath = pathutil.abspath("test.tex")

			expect.equal(#filelist, 1)
			expect.equal(filelist[1], {path="test.tex", abspath=abspath, kind="input"})
			expect.equal(filemap[abspath], filelist[1])
		end)
	end)

	-- Tests for parse_recorder_file
	describe("parse_recorder_file", function()
		it("parse_recorder_file should parse file correctly", function()
			local test_file = "test_recorder.txt"
			local content = "INPUT test.tex\nOUTPUT test.out"
			local file = io.open(test_file, "w")
			assert(file)
			file:write(content)
			file:close()
			io.open("test.tex", "w"):close()
			local abspath_a = pathutil.abspath("test.tex")
			io.open("test.out", "w"):close()
			local abspath_b = pathutil.abspath("test.out")

			local filelist, filemap = reruncheck.parse_recorder_file(test_file, {})
			expect.equal(#filelist, 2)
			expect.equal(filelist[1], {path="test.tex", abspath=abspath_a, kind="input"})
			expect.equal(filelist[2], {path="test.out", abspath=abspath_b, kind="auxiliary"})
			expect.equal(filemap[abspath_a], filelist[1])
			expect.equal(filemap[abspath_b], filelist[2])
		end)
	end)

	-- Tests for collectfileinfo
	describe("collectfileinfo", function()
		it("collectfileinfo should collect information correctly", function()
			io.open("valid_path", "w"):close()
			local abspath = pathutil.abspath("valid_path")
			lfs.touch(abspath, 0, 1337)

			local filelist = {{ path = "valid_path", abspath = abspath, kind = "input" }}
			local auxstatus = {}

			local result = reruncheck.collectfileinfo(filelist, auxstatus)
			expect.equal(result[abspath], {mtime=1337})
		end)
	end)

	-- Tests for comparefileinfo
	describe("comparefileinfo", function()
		it("comparefileinfo should detect changes correctly", function()
			io.open("valid_path", "w"):close()
			local abspath = pathutil.abspath("valid_path")
			lfs.touch(abspath, 0, 1337)

			local filelist = {{ path = "valid_path", abspath = abspath, kind = "input" }}
			local auxstatus = {[abspath]={mtime=0}}

			local rerun, newstatus = reruncheck.comparefileinfo(filelist, auxstatus)
			expect.truthy(rerun)
			expect.equal(newstatus[abspath], {mtime=1337})
		end)
	end)

	-- Tests for comparefiletime
	describe("comparefiletime", function()
		it("comparefiletime should compare times correctly", function()
			io.open("dst", "w"):close()
			lfs.touch("dst", 0, 1337)

			local result = reruncheck.comparefiletime("src", "dst", {src={mtime=2000}})
			expect.truthy(result)
		end)
	end)

	-- Tests for anyNonOutputNewerThan
	describe("anyNonOutputNewerThan", function()
		it("anyNonOutputNewerThan should check files correctly", function()
			io.open("valid_path", "w"):close()
			local abspath_a = pathutil.abspath("valid_path")
			lfs.touch(abspath_a, 0, 1337)

			io.open("reference_file", "w"):close()
			local abspath_b = pathutil.abspath("reference_file")
			lfs.touch(abspath_b, 0, 1336)

			local filelist = {{ path = "valid_path", abspath = abspath_a, kind = "input" }}
			local result = reruncheck.anyNonOutputNewerThan(filelist, "reference_file")
			expect.truthy(result)
		end)
	end)
end)
