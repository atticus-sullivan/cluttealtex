local lester = require 'lester'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect


local pathutil_unix = require 'src_lua.texrunner.pathutil_unix'
local pathutil_windows = require 'src_lua.texrunner.pathutil_windows'

describe('pathutil_unix', function()
	describe('joinpath', function()
		it('/path/to/somewhere', function()
			expect.equal(pathutil_unix.join("/path/", "to", "somewhere"), "/path/to/somewhere")
		end)
	end)
end)

describe('pathutil_windows', function()
	describe('joinpath', function()
		it([[/path/to\somewhere]], function()
			expect.equal(pathutil_windows.join("/path/", "to", "somewhere"), [[/path/to\somewhere]])
		end)
	end)
end)

lester.report() -- Print overall statistic of the tests run.
lester.exit() -- Exit with success if all tests passed.
