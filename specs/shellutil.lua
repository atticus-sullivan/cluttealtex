local lester = require 'lester'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect

local shellutil_unix = require 'src_lua.texrunner.shellutil_unix'
local shellutil_windows = require 'src_lua.texrunner.shellutil_windows'

-- describe('pathutil_unix', function()
-- 	describe('joinpath', function()
-- 		it('/path/to/somewhere', function()
-- 			expect.equal(pathutil_unix.join("/path/", "to", "somewhere"), "/path/to/somewhere")
-- 		end)
-- 	end)
-- end)

describe('shellutil_windows', function()
	describe('escape', function()
		it([[Hello world!]], function()
			expect.equal(shellutil_windows.escape([[Hello world!]]), [["Hello world!"]])
		end)
		it([[Hello" world!]], function()
			expect.equal(shellutil_windows.escape([[Hello" world!]]), [["Hello\" world!"]])
		end)
		it([[Hello\" world!]], function()
			expect.equal(shellutil_windows.escape([[Hello\" world!"]]), [["Hello\\\" world!\""]])
		end)
	end)
end)
