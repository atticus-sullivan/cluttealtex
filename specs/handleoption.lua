local lfs = require 'lfs'
local lester = require 'lester'

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local handleoption = require 'src_lua.texrunner.handleoption'


-- TODO rewrite the tests
describe("handleoption", function()
	before(function() end)
	after(function() end)

	describe("query_options", function()
		-- Test for query_options function with valid long option
		it("should query options with valid long option", function()
			local option, key, no = handleoption._internal.query_options("engine", "long")
			-- it suffices if handle_cli is set, don't check the function
			expect.equal(option, {short="e", long="engine", param=true, handle_cli=option.handle_cli or function()end})
			expect.equal(key, "engine")
			expect.falsy(no)
		end)

		-- Test for query_options with invalid option
		it("should fail when querying invalid long option", function()
			local option, key, _ = handleoption._internal.query_options("invalid_option", "long")
			expect.not_exist(option)
			expect.not_exist(key)
			-- option was not found -> last return value doesn't matter
		end)
	end)

	describe("merge_options", function()
		-- Test for merge_options function
		it("should correctly merge two option tables", function()
			local options1 = { tex_extraoptions = {"opt1", "opt2"}, max_iterations = 3 }
			local options2 = { tex_extraoptions = {"opt3", "opt4"}, skip_first = false }
			local merged_options = handleoption._internal.merge_options(options1, options2)

			expect.equal(merged_options.tex_extraoptions, {"opt3", "opt4"})
			expect.equal(merged_options.max_iterations, 3)
			expect.equal(merged_options.skip_first, false)
		end)
	end)

	describe("handle_boolean_option", function()
		-- Test for handling real boolean option
		it("call handle_cli -- boolean", function()
			local options = {}
			local cli_was_called = 0
			local cfg_was_called = 0
			local option = {
				boolean = true,
				handle_cli = function(options, value)
					options.boolean_option = value
					cli_was_called = cli_was_called + 1
				end,
				handle_cfg = function(_, _)
					cfg_was_called = cfg_was_called + 1
				end,
			}
			expect.not_fail(function()
				handleoption._internal.handle_boolean_option(option, "boolean_option", options, true)
			end)

			expect.equal(options.boolean_option, true)
			expect.equal(cli_was_called, 1)
			expect.equal(cfg_was_called, 0)
		end)

		-- Test for handling an option with a default value
		it("call handle_cli -- default", function()
			local options = {}
			local cli_was_called = 0
			local cfg_was_called = 0
			local option = {
				boolean = false,
				default = "default",
				handle_cli = function(options, value)
					options.non_boolean_option = value
					cli_was_called = cli_was_called + 1
				end,
				handle_cfg = function(_, _)
					cfg_was_called = cfg_was_called + 1
				end,
			}
			expect.not_fail(function()
				handleoption._internal.handle_boolean_option(option, "boolean_option", options, true)
			end)

			expect.equal(options.non_boolean_option, "default")
			expect.equal(cli_was_called, 1)
			expect.equal(cfg_was_called, 0)
		end)

		-- Test for handling a non-bolean option without a default value
		it("call handle_cli -- non-bolean + non-default", function()
			local options = {}
			local cli_was_called = 0
			local cfg_was_called = 0
			local option = {
				boolean = false,
				handle_cfg = function(_, _)
					cfg_was_called = cfg_was_called + 1
				end,
				handle_cli = function(_, _)
					cli_was_called = cli_was_called + 1
				end,
			}
			expect.fail(function()
				handleoption._internal.handle_boolean_option(option, "boolean_option", options, true)
			end)
			expect.equal(cli_was_called, 0)
			expect.equal(cfg_was_called, 0)
		end)

		-- Test for handling a bolean option without a handle_cli key
		it("call handle_cli -- bolean + no handle_cli", function()
			local options = {}
			local cfg_was_called = 0
			local option = {
				boolean = true,
				handle_cfg = function(_, _)
					cfg_was_called = cfg_was_called + 1
				end,
				handle_cli = nil,
			}
			expect.fail(function()
				handleoption._internal.handle_boolean_option(option, "boolean_option", options, true)
			end)
			expect.equal(cfg_was_called, 0)
		end)

		-- Test for handling a default option without a handle_cli key
		it("call handle_cli -- bolean + no handle_cli", function()
			local options = {}
			local cfg_was_called = 0
			local option = {
				boolean = false,
				default = "default",
				handle_cfg = function(_, _)
					cfg_was_called = cfg_was_called + 1
				end,
				handle_cli = nil,
			}
			expect.fail(function()
				handleoption._internal.handle_boolean_option(option, "boolean_option", options, true)
			end)
			expect.equal(cfg_was_called, 0)
		end)
	end)

	describe("handle_table_option", function()
		-- Test for handling table option with handle_cfg defined
		it("calls handle_cfg with table value", function()
			local options = {}
			local cfg_was_called = 0
			local option = {
				handle_cfg = function(options, value)
					options.table_option = value
					cfg_was_called = cfg_was_called + 1
				end,
				handle_cli = nil,
			}
			local test_value = { key = "value" }

			expect.not_fail(function()
				handleoption._internal.handle_table_option(option, "table_option", options, test_value)
			end)

			expect.equal(options.table_option, test_value)
			expect.equal(cfg_was_called, 1)
		end)

		-- Test for handling table option with handle_cfg missing and handle_cli defined
		it("throws error when only handle_cli exists but table value is passed", function()
			local options = {}
			local cli_was_called = 0
			local option = {
				handle_cfg = nil,
				handle_cli = function(_, _)
					cli_was_called = cli_was_called + 1
				end,
			}
			local test_value = { key = "value" }

			expect.fail(function()
				handleoption._internal.handle_table_option(option, "table_option", options, test_value)
			end)
			expect.equal(cli_was_called, 0)
		end)

		-- Test for handling table option with neither handle_cfg nor handle_cli
		it("throws error when both handle_cfg and handle_cli are missing", function()
			local options = {}
			local option = {
				handle_cfg = nil,
				handle_cli = nil,
			}
			local test_value = { key = "value" }

			expect.fail(function()
				handleoption._internal.handle_table_option(option, "table_option", options, test_value)
			end)
		end)
	end)

	describe("handle_config_option", function()
		-- TODO can we somehow mock the option_spec?
		describe("non-accumulating", function()
			-- Test handling a string value with handle_cli
			it("handles string value with handle_cli", function()
				local options = {}
				handleoption._internal.handle_config_option("engine", "test_value", options)
				expect.equal(options, {engine="test_value"})
			end)

			-- Test handling a boolean value
			it("handles boolean value", function()
				local options = {}
				handleoption._internal.handle_config_option("change_directory", true, options)
				expect.equal(options, {change_directory=true})
			end)

			-- Test handling a table value
			it("handles table value", function()
				local options = {}
				local test_value = {{ type = "makeindex", out="xyz" }}
				handleoption._internal.handle_config_option("glossaries", test_value, options)
				expect.equal(options, {glossaries={{
					type="makeindex",
					out="xyz",
					inp="xyo",
					log="xyg",
					path="makeindex",
					cmd=options.glossaries[1].cmd, -- ignore the function
				}}})
			end)

			-- Test handling an unknown type
			it("unsupported value type does not modify options", function()
				local options = {}
				handleoption._internal.handle_config_option("definitely_unknown_option", function() end, options)
				expect.equal(options, {})
			end)
		end)
	end)

	describe("handle_config_defaults", function()
		-- TODO can we somehow mock the option_spec?
		-- doesn't really make sense without this as it modifies an existing option
	end)

	describe("add_custom_cli_options", function()
		-- Test adding a valid custom option
		it("adds valid custom CLI option", function()
			local add_cli_options = {
				new_previously_unset_custom_option = {
					long = "custom1",
					handle_cli = function() end,
				},
			}
			handleoption._internal.add_custom_cli_options(add_cli_options)
			expect.equal(handleoption._internal.query_options("custom1", "long"), add_cli_options.new_previously_unset_custom_option)
		end)

		-- Test warning for duplicate option
		it("skips duplicate option", function()
			local engine = handleoption._internal.query_options("engine", "long")
			local add_cli_options = {
				engine = {
					long = "engine",
					handle_cli = function() end,
				}
			}
			handleoption._internal.add_custom_cli_options(add_cli_options)
			expect.equal(handleoption._internal.query_options("engine", "long"), engine)
		end)

		-- Test skipping invalid custom options
		it("skips invalid custom options", function()
			local add_cli_options = {
				invalid_option = {
					long = "custom3"
					-- no handle_ set
				}
			}
			handleoption._internal.add_custom_cli_options(add_cli_options)
			expect.equal(handleoption._internal.query_options("custom3", "long"), nil)
		end)
	end)

	describe("parse_config_file", function()
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

		-- Test parsing a valid configuration file
		it("parses valid configuration file", function()
			-- Create a sample config file
			local cfgfile_path = tmp_dir .. "/.cluttealtexrc.lua"
			local cfg_content = [[return {
	options = {
		file = "main.tex",
		output_directory = "tex-aux",
		change_directory = true,
		engine = "pdflatex",
		biber = true,
		glossaries = {{type="makeindex", out="acr", inp="acn", log="alg"}},
		max_iterations = "50",
		quiet = "0",
	},
	defaults = {
		watch = "inotify",
	}
}]]
			local file = assert(io.open(cfgfile_path, "w"))
			file:write(cfg_content)
			file:close()

			local options, inputfile = handleoption._internal.parse_config_file()
			expect.equal(options, {
				output_directory = "tex-aux",
				change_directory = true,
				engine = "pdflatex",
				biber = "biber",
				glossaries = {{type="makeindex", path="makeindex", out="acr", inp="acn", log="alg", cmd=options.glossaries[1].cmd}},
				max_iterations = 50,
				quiet = 0,
			})
			expect.equal(inputfile, "main.tex")
			local watch = handleoption._internal.query_options("watch", "long")
			expect.equal(watch, {long="watch", default="inotify", handle_cli=watch.handle_cli, param=true})
		end)

		-- Test invalid config structure
		it("throws error for invalid config structure -- syntax error", function()
			-- Create a sample config file
			local cfgfile_path = tmp_dir .. "/.cluttealtexrc.lua"
			local cfg_content = [[return {
	options = {
}]]
			local file = assert(io.open(cfgfile_path, "w"))
			file:write(cfg_content)
			file:close()

			expect.fail(function()
				handleoption._internal.parse_config_file()
			end)
		end)

		-- Test invalid config structure
		it("throws error for invalid config structure -- no return", function()
			-- Create a sample config file
			local cfgfile_path = tmp_dir .. "/.cluttealtexrc.lua"
			local cfg_content = [[]]
			local file = assert(io.open(cfgfile_path, "w"))
			file:write(cfg_content)
			file:close()

			expect.fail(function()
				handleoption._internal.parse_config_file()
			end)
		end)
	end)

	describe("parse_command_line_options", function()
		-- Test parsing valid command-line options
		it("parses valid options", function()
			local options, non_option_index = handleoption._internal.parse_command_line_options({"-e", "pdflatex"})
			expect.equal(options.engine, "pdflatex")
			expect.equal(non_option_index, 3)
		end)

		-- Test handling invalid option
		it("throws error for invalid option", function()
			expect.fail(function()
				handleoption._internal.parse_command_line_options({"--non-exitant-option"})
			end)
		end)
	end)

	describe("handle_input_file", function()
		-- Test handling single input file
		it("handles single input file", function()
			local result = handleoption._internal.handle_input_file({ "file.tex" }, nil, 1)
			expect.equal(result, "file.tex")
		end)

		-- Test handling single input file
		it("handles single input file", function()
			local result = handleoption._internal.handle_input_file({}, "file.tex", 1)
			expect.equal(result, "file.tex")
		end)

		-- Test error for multiple input files
		it("throws error for multiple input files", function()
			expect.fail(function()
				handleoption._internal.handle_input_file({ "file1.tex", "file2.tex" }, nil, 1)
			end)
		end)

		-- Test error for multiple input files
		it("throws error for multiple input files", function()
			expect.fail(function()
				handleoption._internal.handle_input_file({ "file1.ted" }, "xaz", 1)
			end)
		end)
	end)
end)
