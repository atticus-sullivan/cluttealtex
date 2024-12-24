local lfs = require 'lfs'
local lester = require 'lester'

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local auxfile = require 'src_lua.texrunner.auxfile'

describe('auxfile', function()

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


	describe('parse_aux_file', function()

		it('should parse a single aux file without dependencies', function()
			-- Create a sample aux file
			local auxfile_path = tmp_dir .. "/test.aux"
			local aux_content = "\\@input{other.aux}\n"
			local file = assert(io.open(auxfile_path, "w"))
			file:write(aux_content)
			file:close()

			-- Run the function
			local report = auxfile.parse_aux_file(auxfile_path, tmp_dir)
			expect.not_exist(report.made_new_directory)
		end)

		it('should create missing directories for unresolved aux files', function()
			-- Create a sample aux file
			local auxfile_path = tmp_dir .. "/test.aux"
			local aux_content = "\\@input{missing/missing.aux}\n"
			local file = assert(io.open(auxfile_path, "w"))
			file:write(aux_content)
			file:close()

			-- Run the function
			local report = auxfile.parse_aux_file(auxfile_path, tmp_dir)
			expect.truthy(report.made_new_directory)
		end)


		it([[should not enter infinite recursion with cyclic \@input references]], function()
			-- Create cyclically-referencing aux files
			local file1_path = tmp_dir .. "/file1.aux"
			local file2_path = tmp_dir .. "/file2.aux"

			-- File 1 references file 2
			local file1_content = "\\@input{file2.aux}\n"
			local file1 = assert(io.open(file1_path, "w"))
			file1:write(file1_content)
			file1:close()

			-- File 2 references file 1
			local file2_content = "\\@input{file1.aux}\n"
			local file2 = assert(io.open(file2_path, "w"))
			file2:write(file2_content)
			file2:close()

			-- Run the function
			local report = auxfile.parse_aux_file(file1_path, tmp_dir)

			-- Expect no infinite recursion (execution completes) and no new directories are made
			expect.not_exist(report.made_new_directory)
			end)

	end)

	describe('extract_bibtex_from_aux_file', function()

		it('should extract BibTeX lines from a single aux file', function()
			-- Create a sample aux file
			local auxfile_path = tmp_dir .. "/test.aux"
			local aux_content = [[
\citation{key1}
\bibdata{refs}
\bibstyle{plain}
]]
			local file = assert(io.open(auxfile_path, "w"))
			file:write(aux_content)
			file:close()

			-- Run the function
			local biblines = auxfile.extract_bibtex_from_aux_file(auxfile_path, tmp_dir)
			expect.equal(#biblines, 3)
			expect.equal(biblines[1], "\\citation{key1}")
			expect.equal(biblines[2], "\\bibdata{refs}")
			expect.equal(biblines[3], "\\bibstyle{plain}")
		end)

		it('should recursively extract BibTeX lines from nested aux files', function()
			-- Create a main aux file
			local main_auxfile_path = tmp_dir .. "/test.aux"
			local main_aux_content = "\\@input{sub.aux}\n"
			local file = assert(io.open(main_auxfile_path, "w"))
			file:write(main_aux_content)
			file:close()

			-- Create a nested aux file
			local sub_auxfile_path = tmp_dir .. "/sub.aux"
			local sub_aux_content = [[
\citation{key2}
\bibstyle{alpha}
]]
			local subfile = assert(io.open(sub_auxfile_path, "w"))
			subfile:write(sub_aux_content)
			subfile:close()

			-- Run the function
			local biblines = auxfile.extract_bibtex_from_aux_file(main_auxfile_path, tmp_dir)
			expect.equal(#biblines, 2)
			expect.equal(biblines[1], "\\citation{key2}")
			expect.equal(biblines[2], "\\bibstyle{alpha}")
		end)


		it([[should not enter infinite recursion with cyclic \@input references in BibTeX extraction]], function()
			-- Create cyclically-referencing aux files
			local file1_path = tmp_dir .. "/file1.aux"
			local file2_path = tmp_dir .. "/file2.aux"

			-- File 1 references file 2 and has a citation
			local file1_content = "\\@input{file2.aux}\n\\citation{key1}\n"
			local file1 = assert(io.open(file1_path, "w"))
			file1:write(file1_content)
			file1:close()

			-- File 2 references file 1 and has a BibTeX style
			local file2_content = "\\@input{file1.aux}\n\\bibstyle{plain}\n"
			local file2 = assert(io.open(file2_path, "w"))
			file2:write(file2_content)
			file2:close()

			-- Run the function
			local biblines = auxfile.extract_bibtex_from_aux_file(file1_path, tmp_dir)

			-- Expect no infinite recursion (execution completes) and valid BibTeX lines are extracted
			expect.equal(#biblines, 2)
			expect.equal(biblines[1], "\\bibstyle{plain}")
			expect.equal(biblines[2], "\\citation{key1}")
		end)

	end)

end)
