local lester = require 'lester'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local watcher   = require 'src_lua.texrunner.watcher'
local shellutil = require 'src_lua.texrunner.shellutil'

describe("watcher", function()
	describe("gather_input_files_to_watch", function()
		it("returns an empty list if filelist is empty", function()
			local max_watches = 10
			local options = { watch_inc_exc = nil }
			local filelist = {}

			local result = watcher.gather_input_files_to_watch(max_watches, options, filelist)
			expect.equal(#result, 0)
		end)

		it("filters files based on provided watch_inc_exc", function()
			local max_watches = 10
			local options = { watch_inc_exc = { { type = "only_ext", param = "tex" } } }
			local filelist = {
				{ abspath = "file1.tex", kind = "input" },
				{ abspath = "file2.pdf", kind = "input" },
				{ abspath = "file3.tex", kind = "output" },
			}

			local result = watcher.gather_input_files_to_watch(max_watches, options, filelist)
			expect.equal(#result, 1)
			expect.equal(result[1], "file1.tex")
		end)

		it("limits the number of files to max_watches", function()
			local max_watches = 2
			local options = { watch_inc_exc = nil }
			local filelist = {
				{ abspath = "file1.tex", kind = "input" },
				{ abspath = "file2.tex", kind = "input" },
				{ abspath = "file3.tex", kind = "input" },
			}

			local result = watcher.gather_input_files_to_watch(max_watches, options, filelist)
			expect.equal(#result, 3)
		end)
	end)

	-- Test suite for get_do_watch
	describe("get_do_watch", function()
		local has_fswatch = shellutil.has_command("fswatch")
		it("returns a watcher function for fswatch if available", function()
			local options = { watch = "fswatch" }
			local watcher_func, max_watches = watcher.get_do_watch(options)
			expect.exist(watcher_func)
			expect.equal(max_watches, -1)
		end, has_fswatch)

		local has_inotifywait = shellutil.has_command("inotifywait")
		it("returns a watcher function for inotifywait if available", function()
			local options = { watch = "inotifywait" }
			local watcher_func, max_watches = watcher.get_do_watch(options)
			expect.exist(watcher_func)
			expect.equal(max_watches, 1024)
		end, has_inotifywait)
	end)
end)
