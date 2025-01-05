local lester = require 'lester'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local option_spec = require 'src_lua.texrunner.option_spec'

describe("option_spec", function()
	describe("init_hooks", function()
		it("initializes hooks with empty tables", function()
			local options = {}
			local spec = {}
			option_spec.init_hooks(options, spec)
			expect.equal(options, {
				hooks = {
					tex_injection = {},
					post_compile = {},
					suggestion_file_based = {},
					suggestion_execlog_based = {},
					post_build = {},
				}
			})
		end)

		it("invokes suggestion handlers if specified in the spec", function()
			local called = {file_based = false, execlog_based = false}
			local options = {}
			local spec = {
				optionA = {
					suggestion_handlers = {
						file_based = function(_) called.file_based = true end,
						execlog_based = function(_) called.execlog_based = true end,
					}
				}
			}
			option_spec.init_hooks(options, spec)
			expect.truthy(called.file_based)
			expect.truthy(called.execlog_based)
		end)
	end)

	describe("split", function()
		it("splits a string with unescaped delimiters", function()
			local result = option_spec._internal.split("a:b:c")
			expect.equal(result, {"a", "b", "c"})
		end)

		it("handles escaped delimiters correctly", function()
			local result = option_spec._internal.split("a\\:b:c")
			expect.equal(result, {"a:b", "c"})
		end)

		it("handles trailing characters correctly", function()
			local result = option_spec._internal.split("a:b:c\\")
			expect.equal(result, {"a", "b", "c"})
		end)
	end)

	describe("parse_glossaries_option_from_table", function()
		it("parses a valid glossaries table with default values", function()
			local input = {type = "makeindex", out = "output.idx"}
			local result, err = option_spec._internal.parse_glossaries_option_from_table(input)
			expect.not_exist(err)
			expect.equal(result, {
				type = "makeindex",
				out  = "output.idx",
				inp  = "output.ido",
				log  = "output.idg",
				path = "makeindex",
				cmd  = result.cmd, -- don't check function
			})
		end)

		it("returns an error for invalid types", function()
			local input = {type = "unsupported", out = "output.idx"}
			local result, err = option_spec._internal.parse_glossaries_option_from_table(input)
			expect.not_exist(result)
			expect.exist(err)
			expect.equal(err, 'Invalid glossaries parameter. "unsupported" is unsupported')
		end)

		it("returns an error if 'out' is not set", function()
			local input = {type = "makeindex"}
			local result, err = option_spec._internal.parse_glossaries_option_from_table(input)
			expect.not_exist(result)
			expect.exist(err)
			expect.equal(err, "'out' must be set")
		end)
	end)

	describe("parse_glossaries_option_from_string", function()
		it("parses a valid glossaries string", function()
			local input = "makeindex:output.idx:input.ido:logfile.log:mycustompath"
			local result, err = option_spec._internal.parse_glossaries_option_from_string(input)
			expect.not_exist(err)
			expect.equal(result, {
				type = "makeindex",
				out  = "output.idx",
				inp  = "input.ido",
				log  = "logfile.log",
				cmd  = result.cmd, -- don't check function
				path = "mycustompath",
			})
		end)

		it("returns an error for invalid glossaries strings", function()
			local input = "makeindex"
			local result, err = option_spec._internal.parse_glossaries_option_from_string(input)
			expect.not_exist(result)
			expect.exist(err)
			expect.truthy(err:find("Error on splitting the glossaries parameter"))
		end)

		it("handles optional fields gracefully", function()
			local input = "makeindex:output.idx"
			local result, err = option_spec._internal.parse_glossaries_option_from_string(input)
			expect.not_exist(err)
			expect.equal(result, {
				type = "makeindex",
				out  = "output.idx",
				inp  = "output.ido",
				log  = "output.idg",
				cmd  = result.cmd, -- don't check function
				path = "makeindex",
			})
		end)
	end)
end)
