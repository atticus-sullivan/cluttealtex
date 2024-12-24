local lfs = require 'lfs'
local lester = require 'lester'

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local tex_engine = require 'src_lua.texrunner.tex_engine'

describe("Engine command generation", function()

	-- Basic setup: known engines
	local KnownEngines = tex_engine.KnownEngines

	it("should generate a valid command for pdftex with basic options", function()
		local engine = KnownEngines["pdftex"]
		local options = {
			fmt = "plain",
			halt_on_error = true,
			interaction = "batchmode",
			file_line_error = true,
			synctex = "1"
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(
			command,
			"pdftex -recorder -fmt=plain -halt-on-error -interaction=batchmode -file-line-error -synctex='1' 'inputfile.tex'"
		)
	end)
--
	it("should generate a valid command for xetex with advanced options", function()
		local engine = KnownEngines["xetex"]
		local options = {
			jobname = "outputfile",
			output_directory = "./build",
			shell_escape = true,
			extraoptions = {"-custom-option"}
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(
			command,
			"xetex -recorder -shell-escape -jobname='outputfile' -output-directory='./build' -custom-option 'inputfile.tex'"
		)
	end)

	it("should include xetex-specific options when applicable", function()
		local engine = KnownEngines["xetex"]
		local options = {
			output_format = "dvi"
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(
			command,
			"xetex -recorder -no-pdf 'inputfile.tex'"
		)
	end)

	it("should handle the default executable if engine_executable is not specified", function()
		local engine = KnownEngines["latex"]
		local options = {
			halt_on_error = true,
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(command, "latex -recorder -halt-on-error 'inputfile.tex'")
	end)

	it("should override the executable if engine_executable is specified", function()
		local engine = KnownEngines["latex"]
		local options = {
			halt_on_error = true,
			engine_executable = "customlatex"
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(command, "customlatex -recorder -halt-on-error 'inputfile.tex'")
	end)

	it("should handle no-shell-escape when shell_escape is false", function()
		local engine = KnownEngines["pdftex"]
		local options = {
			shell_escape = false
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(command, "pdftex -recorder -no-shell-escape 'inputfile.tex'")
	end)

	it("should handle no output format or draftmode for engines that don't support PDF", function()
		local engine = KnownEngines["tex"]
		local options = {}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(command, "tex -recorder 'inputfile.tex'")
	end)

	it("should handle extra options passed to the engine", function()
		local engine = KnownEngines["xelatex"]
		local options = {
			extraoptions = {"-debug", "--strict"}
		}

		local command = engine:build_command("inputfile.tex", options)
		expect.equal(command, "xelatex -recorder -debug --strict 'inputfile.tex'")
	end)
end)
