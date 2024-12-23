local lester = require("lester")

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local option = require 'src_lua.texrunner.option'

lester.describe("option", function()
	-- Mock function for querying long options
	local function query_long_options(option_name)
		local options = {
			test = { long = "test", param = false, boolean = true },
			param = { long = "param", param = true, default = "default" },
			["no-flag"] = { long = "flag", param = false, boolean = true },
		}
		local option = options[option_name] or options["no-" .. option_name]
		return option, option and option.long, option_name:match("^no%-")
	end

	-- Mock function for querying short options
	local function query_short_options(option_name)
		local options = {
			t = { short = "t", param = false, boolean = true },
			p = { short = "p", param = true, default = "default" },
		}
		local option = options[option_name]
		return option, option and option.short, false
	end

	lester.it("Parses long options without parameters", function()
		local args = { "--test" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "test", true } })
	end)

	lester.it("Parses long options with parameters", function()
		local args = { "--param=value" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "param", "value" } })
	end)

	lester.it("Parses long options with parameters", function()
		local args = { "--param", "value" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "param", "value" } })
	end)

	lester.it("Uses default value for long options with missing parameters", function()
		local args = { "--param" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "param", "default" } })
	end)

	lester.it("Parses negated long options", function()
		local args = { "--no-flag" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "flag", false } })
	end)

	lester.it("Parses short options without parameters", function()
		local args = { "-t" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "t", true } })
	end)

	lester.it("Parses short options with parameters", function()
		local args = { "-p", "value" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "p", "value" } })
	end)

	lester.it("Parses short options with parameters", function()
		local args = { "-p=value" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "p", "value" } })
	end)

	lester.it("Uses default value for short options with missing parameters", function()
		local args = { "-p" }
		local result = option.parseoption(args, query_long_options, query_short_options)
		lester.expect.equal(result, { { "p", "default" } })
	end)

	lester.it("Handles missing option error", function()
		local args = { "--unknown" }
		lester.expect.fail(function()
			option.parseoption(args, query_long_options, query_short_options)
		end)
	end)

	lester.it("Handles missing parameter error", function()
		local args = { "--param", "--another" }
		lester.expect.fail(function()
			option.parseoption(args, query_long_options, query_short_options)
		end)
	end)
end)

lester.describe("Handle Option Parameter Tests", function()
	local function mock_option(param, boolean, default)
		return {
			param = param,
			boolean = boolean,
			default = default,
		}
	end

	lester.it("Resolves parameter value from next argument", function()
		local moption = mock_option(true, false)
		local result, inc = option._internal.handle_option_param(moption, "test", false, nil, "value")
		lester.expect.equal(result, { "test", "value" })
		lester.expect.equal(inc, 1)
	end)

	lester.it("Uses default parameter value", function()
		local moption = mock_option(true, false, "default")
		local result, inc = option._internal.handle_option_param(moption, "test", false, nil, nil)
		lester.expect.equal(result, { "test", "default" })
		lester.expect.equal(inc, 0)
	end)

	lester.it("Handles boolean option without parameter", function()
		local moption = mock_option(false, true)
		local result, inc = option._internal.handle_option_param(moption, "flag", false, nil, nil)
		lester.expect.equal(result, { "flag", true })
		lester.expect.equal(inc, 0)
	end)

	lester.it("Handles negated boolean option", function()
		local moption = mock_option(false, true)
		local result, inc = option._internal.handle_option_param(moption, "flag", true, nil, nil)
		lester.expect.equal(result, { "flag", false })
		lester.expect.equal(inc, 0)
	end)
end)
