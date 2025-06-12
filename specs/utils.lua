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

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local utils    = require "src_lua.texrunner.utils"
local pathutil = require "texrunner.pathutil"
local fsutil   = require "texrunner.fsutil"

describe("utils", function()
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

	describe("prepend_env", function()
		it("should prepend environment variables correctly", function()
			local var = "TEST_ENV_VAR"
			os.setenv(var, "initial")
			utils.prepend_env(var, "prepend", ":")
			expect.equal(os.getenv(var), "prepend:initial")
		end)
	end)

	describe("env_setup", function()
		it("should set up the environment correctly", function()
			local options = {
				change_directory = true,
				output_directory = tmp_dir,
				output = "main.pdf",
				bibtex = true,
				biber = true,
			}
			local original_wd = original_dir
			local env = utils.env_setup(options, original_wd)

			expect.equal(env.original_wd, original_dir)
			expect.equal(options.output_directory, ".")
			expect.truthy(os.getenv("TEXINPUTS"):find(original_dir))
			expect.truthy(os.getenv("BIBINPUTS"):find(original_dir))
			expect.equal(os.getenv("max_print_line"), "19999")
		end)
	end)

	describe("prepare_output_directory", function()
		it("should prepare the output directory correctly", function()
			local options = {
				fresh = true,
				output_directory = nil,
			}
			local inputfile = tmp_dir .. "/test.tex"
			local jobname = "testjob"
			io.open(inputfile, "w"):close()

			utils.prepare_output_directory(options, inputfile, jobname)
			expect.exist(options.output_directory)
			expect.truthy(fsutil.isdir(options.output_directory))
		end)
	end)

	describe("initialize_options", function()
		it("should initialize options correctly", function()
			local options = {
				jobname = nil,
				output_format = "pdf",
			}
			local engine = {
				dvi_extension = "dvi",
			}
			local inputfile = "test.tex"

			local jobname, extension = utils.initialize_options(options, engine, inputfile)
			expect.equal(jobname, "test")
			expect.equal(extension, "pdf")
			expect.equal(options.output, "test.pdf")
		end)
	end)

	describe("construct_tex_options", function()
		it("should construct tex options correctly", function()
			local options = {
				engine_executable = "pdflatex",
				interaction = "nonstopmode",
				file_line_error = true,
				halt_on_error = true,
				synctex = 1,
				output_directory = tmp_dir,
				shell_escape = true,
				shell_restricted = false,
				jobname = "test",
				fmt = "plain",
				tex_extraoptions = "",
				output_format = "pdf",
			}
			local engine = {
				supports_pdf_generation = true,
			}
			local tex_options = utils.construct_tex_options(options, engine)

			expect.equal(tex_options.engine_executable, "pdflatex")
			expect.equal(tex_options.interaction, "nonstopmode")
			expect.equal(tex_options.file_line_error, true)
			expect.equal(tex_options.halt_on_error, true)
			expect.equal(tex_options.synctex, 1)
			expect.equal(tex_options.output_directory, tmp_dir)
			expect.equal(tex_options.shell_escape, true)
			expect.equal(tex_options.shell_restricted, false)
			expect.equal(tex_options.jobname, "test")
			expect.equal(tex_options.fmt, "plain")
		end)
	end)

	describe("path_in_output_directory", function()
		it("should generate the correct path in output directory", function()
			local options = {
				output_directory = tmp_dir,
			}
			local ext = "pdf"
			local jobname = "testjob"
			local path = utils.path_in_output_directory(ext, options, jobname)

			expect.equal(path, pathutil.join(tmp_dir, "testjob.pdf"))
		end)
	end)
end)
