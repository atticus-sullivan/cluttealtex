-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local lester = require 'lester'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local safename = require 'src_lua.texrunner.safename'

-- Begin testing
describe("TeX Input Escaping Module", function()
	local engine_mock = { name = "pdftex" } -- Mock engine for testing

	-- Test dounsafechar
	describe("dounsafechar", function()
		local dounsafechar = safename._internal.dounsafechar

		it("should escape space to underscore", function()
			expect.equal(dounsafechar(" "), "_")
		end)

		it("should escape other characters to _xx format", function()
			expect.equal(dounsafechar("!"), "_21")
			expect.equal(dounsafechar("\n"), "_0a")
			expect.equal(dounsafechar("A"), "_41")
		end)
	end)

	-- Test escapejobname
	describe("escapejobname", function()
		it("should escape spaces and special characters", function()
			local result = safename.escapejobname("hello world!")
			expect.equal(result, "hello_world!")
		end)

		it("should handle empty strings", function()
			local result = safename.escapejobname("")
			expect.equal(result, "")
		end)

		it("should handle strings with only special characters", function()
			local result = safename.escapejobname("\"$%&'();<>\\^`|")
			expect.equal(result, "_22_24_25_26_27_28_29_3b_3c_3e_5c_5e_60_7c")
		end)
	end)

	-- Test handlespecialchar
	describe("handlespecialchar", function()
		local handlespecialchar = safename._internal.handlespecialchar

		it("should escape special TeX characters", function()
			local result = handlespecialchar("\\%{}~#")
			expect.equal(result, "~\\\\~\\%~\\{~\\}~\\~~\\#")
		end)

		it("should leave normal characters unchanged", function()
			local result = handlespecialchar("normal text")
			expect.equal(result, "normal text")
		end)
	end)

	-- Test handlespaces
	describe("handlespaces", function()
		local handlespaces = safename._internal.handlespaces

		it("should replace sequences of spaces with ~", function()
			local result = handlespaces("hello  world   !")
			expect.equal(result, "hello ~ world ~ ~ !")
		end)

		it("should handle strings with no spaces", function()
			local result = handlespaces("text")
			expect.equal(result, "text")
		end)
	end)

	-- Test handlenonascii
	describe("handlenonascii", function()
		local handlenonascii = safename._internal.handlenonascii

		it("should wrap non-ASCII characters in \\detokenize", function()
			local result = handlenonascii("hello åäö")
			expect.equal(result, "hello \\detokenize{åäö}")
		end)

		it("should leave ASCII characters unchanged", function()
			local result = handlenonascii("hello")
			expect.equal(result, "hello")
		end)
	end)

	-- Test safeinput
	describe("safeinput", function()
		it("should handle simple inputs safely", function()
			local result = safename.safeinput("hello", engine_mock)
			expect.equal(result, "\\input\"hello\"")
		end)

		it("should escape special characters and spaces", function()
			local result = safename.safeinput("hello world!", engine_mock)
			expect.equal(result, "\\input\"hello world!\"")
		end)

		it("should wrap non-ASCII characters for pdftex engine", function()
			local result = safename.safeinput("text åäö", engine_mock)
			expect.equal(result, [[\begingroup\escapechar-1\let~\string\edef\x{"text \detokenize{åäö}" }\expandafter\endgroup\expandafter\input\x]])
		end)

		it("should handle empty input strings", function()
			local result = safename.safeinput("", engine_mock)
			expect.equal(result, "\\input\"\"")
		end)

		it("should behave differently with non-pdftex engines", function()
			local custom_engine = { name = "luatex" }
			local result = safename.safeinput("text åäö", custom_engine)
			expect.equal(result, [[\input"text åäö"]])
		end)
	end)
end)
