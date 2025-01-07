local lester = require 'lester'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local option_spec = require 'src_lua.texrunner.option_spec'
local orig_spec = option_spec.spec

describe("option_spec", function()
	describe("init_hooks", function()
		it("initializes hooks with empty tables", function()
			local options = {}
			local spec = {}
			option_spec.spec = spec
			option_spec.init_hooks(options)
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
			option_spec.spec = spec
			option_spec.init_hooks(options)
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

	describe("usage_ele", function()
		it("handles options with both long and short names", function()
			local opt = {
				short = "o",
				long = "option",
				help = { text = "An example option", param = "value", ordering = 1 },
				boolean = false,
			}
			local alignment = { short = 0, long = 0, ordering = 0 }

			local result = option_spec._internal.usage_ele("optname", opt, alignment)

			expect.equal(result, {
				short    = "-o,",
				long     = "--option",
				text     = "An example option",
				ordering = 1,
				longLine = nil,
			})
			expect.equal(alignment, {
				short    = 4,
				long     = 10,
				ordering = 1,
			})
		end)

		it("handles options without a short name", function()
			local opt = {
				long = "option",
				param = true,
				help = { text = "An example option without short name", param = "value" },
				boolean = false,
			}
			local alignment = { short = 0, long = 0, ordering = 0 }

			local result = option_spec._internal.usage_ele("optname", opt, alignment)

			expect.equal(result, {
				short    = "   ",
				long     = "--option=value",
				text     = "An example option without short name",
				ordering = nil,
				longLine = nil,
			})
			expect.equal(alignment, {
				short    = 4,
				long     = 16,
				ordering = 0,
			})
		end)

		it("handles boolean options with long names", function()
			local opt = {
				long = "enable-feature",
				help = { text = "Enable or disable a feature", param = nil },
				boolean = true,
			}
			local alignment = { short = 0, long = 0, ordering = 0 }

			local result = option_spec._internal.usage_ele("feature", opt, alignment)

			expect.equal(result, {
				short    = "   ",
				long     = "--[no-]enable-feature",
				text     = "Enable or disable a feature",
				ordering = nil,
				longLine = nil,
			})
			expect.equal(alignment, {
				short    = 4,
				long     = 23,
				ordering = 0,
			})
		end)

		it("handles options without help text or ordering", function()
			local opt = {
				short = "x",
				long = "example",
				boolean = false,
			}
			local alignment = { short = 0, long = 0, ordering = 0 }

			local result = option_spec._internal.usage_ele("example", opt, alignment)

			expect.equal(result, {
				short    = "-x,",
				long     = "--example",
				text     = "",
				ordering = nil,
				longLine = false,
			})
			expect.equal(alignment, {
				short    = 4,
				long     = 11,
				ordering = 0,
			})
		end)
	end)

	describe("usage", function()
		it("generates usage output with aligned options", function()
			option_spec.spec = {
				opt1 = {
					short = "o",
					long = "option1",
					help = { text = "First option", param = "param", ordering = 1 },
					boolean = false,
				},
				opt2 = {
					long = "option2",
					help = { text = "Second option without short name", param = "VALUE", ordering = 2 },
					boolean = false,
					param = true,
				},
				opt3 = {
					short = "e",
					long = "enable-feature",
					help = { text = "Enable or disable a feature", param = nil, ordering = nil },
					boolean = true,
				},
			}

			local captured_output = {}
			local old_write = io.write
			io.write = function(...)
				local args = {...}
				for _, v in ipairs(args) do
					table.insert(captured_output, v)
				end
			end

			option_spec.usage({[0]="cluttealtex"})

			io.write = old_write

			-- Verify that the output contains the expected sections
			local output_str = table.concat(captured_output, "")
			expect.equal(output_str, [[CluttealTeX: Process TeX files without cluttering your working directory

Usage:
  cluttealtex [options] [--] FILE.tex

Options:
  -o, --option1              First option
      --option2=VALUE        Second option without short name
  -e, --[no-]enable-feature  Enable or disable a feature


For a more detailed reference see 'texdoc cluttealtex' or
    'https://github.com/atticus-sullivan/cluttealtex/releases/download/nil/cluttealtex.pdf'

When run, cluttealtex checks for a config file named '.cluttealtexrc.lua' in your current working directory
(see the detailed docs for more information on how this works)
]])
		end)

		it("handles empty spec gracefully", function()
			option_spec.spec = {}

			local captured_output = {}
			local old_write = io.write
			io.write = function(...)
				local args = {...}
				for _, v in ipairs(args) do
					table.insert(captured_output, v)
				end
			end

			option_spec.usage({[0]="cluttealtex"})

			io.write = old_write

			-- Verify that the output still includes headers but no options
			local output_str = table.concat(captured_output, "")
			expect.equal(output_str, [[CluttealTeX: Process TeX files without cluttering your working directory

Usage:
  cluttealtex [options] [--] FILE.tex

Options:


For a more detailed reference see 'texdoc cluttealtex' or
    'https://github.com/atticus-sullivan/cluttealtex/releases/download/nil/cluttealtex.pdf'

When run, cluttealtex checks for a config file named '.cluttealtexrc.lua' in your current working directory
(see the detailed docs for more information on how this works)
]])
		end)

		it("generates usage output with aligned options", function()
			option_spec.spec = orig_spec

			local captured_output = {}
			local old_write = io.write
			io.write = function(...)
				local args = {...}
				for _, v in ipairs(args) do
					table.insert(captured_output, v)
				end
			end

			option_spec.usage({[0]="cluttealtex"})

			io.write = old_write

			-- Verify that the output contains the expected sections
			local output_str = table.concat(captured_output, "")
			for line in output_str:gmatch("(.-)\n") do
				expect.not_fail(function()
					assert(#line <= 120, ("No line should be longer than 120, but\n'%s'\nwas %d long"):format(line, #line))
				end)
			end
		end)
	end)
end)
