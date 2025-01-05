local lester = require 'lester'
local lfs = require 'lfs'

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect
local before   = lester.before
local after    = lester.after

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local typeset_hooks = require 'src_lua.texrunner.typeset_hooks'

describe("typeset_hooks", function()

	local mock_options
	local mock_args
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
		lfs.mkdir("output")


		mock_options = {
			includeonly = "Chapter1,Chapter2",
			memoize_opts = {"opt1", "opt2"},
			quiet = 2,
			output_directory = "./output",
			makeindex = "makeindex",
			glossaries = {
				{ inp = "glo", out = "gls", cmd = function(_) return "makeglossaries" end }
			},
			bibtex = "bibtex",
			biber = "biber",
			memoize = "memoize",
			sagetex = "sage",
		}

		mock_args = {
			filelist = {},
			auxstatus = {},
			path_in_output_directory = function(ext)
				return "./output/document." .. ext
			end,
			original_wd = "./",
			bibtex_aux_hash = "oldhash",
		}
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

	it("should generate includeonly injection", function()
		local result = typeset_hooks.includeonly(mock_options, {}, "")
		expect.equal(result, "\\includeonly{Chapter1,Chapter2}")
	end)

	it("should generate memoize injection", function()
		local result = typeset_hooks.memoize(mock_options, {}, "")
		expect.equal(result, "\\PassOptionsToPackage{no memo dir,extract=no}{memoize}")
	end)

	it("should generate memoize_opts injection", function()
		local result = typeset_hooks.memoize_opts(mock_options, {}, "")
		expect.equal(result, "\\PassOptionsToPackage{opt1,opt2}{memoize}")
	end)

	it("should handle quiet injection", function()
		local result = typeset_hooks.quiet(mock_options, {interaction = "nonstopmode"}, "")
		expect.truthy(result:find("\\AddToHook{begindocument/end}%[quietX%]{\\hbadness=99999 \\hfuzz=9999pt}"))
		expect.truthy(result:find("\\AddToHook{begindocument/end}%[quiet%]{\\nonstopmode}"))
		expect.truthy(result:find("\\AddToHook{enddocument/info}%[quiet%]{\\batchmode}"))
	end)

	it("should generate minted options injection", function()
		local result = typeset_hooks.ps_minted(mock_options, {}, "")
		expect.equal(result, "\\PassOptionsToPackage{outputdir=./output}{minted}")
	end)

	it("should generate epstopdf options injection", function()
		local result = typeset_hooks.ps_epstopdf(mock_options, {}, "")
		expect.equal(result, "\\PassOptionsToPackage{outdir=./output/}{epstopdf}")
	end)

	it("should yield correct makeindex command", function()
		table.insert(mock_args.filelist, {path = "index.idx", abspath = "./output/index.idx"})
		local co = coroutine.create(function()
			typeset_hooks.makeindex(mock_options, mock_args)
		end)
		local status, ret
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.truthy(ret:find("makeindex"))

		-- check if only yields one command
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.not_exist(ret)

		-- check if terminated
		status, ret = coroutine.resume(co)
		expect.falsy(status)
		expect.equal(ret, "cannot resume dead coroutine")
	end)

	it("should yield correct glossaries command", function()
		table.insert(mock_args.filelist, {path = "glossary.glo", abspath = "./output/glossary.glo"})
		local co = coroutine.create(function()
			typeset_hooks.glossaries(mock_options, mock_args)
		end)
		local status, ret
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.equal(ret, "makeglossaries")

		-- check if only yields one command
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.not_exist(ret)

		-- check if terminated
		status, ret = coroutine.resume(co)
		expect.falsy(status)
		expect.equal(ret, "cannot resume dead coroutine")
	end)

	it("should yield correct BibTeX command", function()
		local file = io.open("output/document.aux", "w")
		assert(file)
		file:close()

		local co = coroutine.create(function()
			typeset_hooks.bibtex(mock_options, mock_args)
		end)
		local status, ret
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.truthy(ret:find("bibtex"))

		-- check if only yields one command
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.not_exist(ret)

		-- check if terminated
		status, ret = coroutine.resume(co)
		expect.falsy(status)
		expect.equal(ret, "cannot resume dead coroutine")
	end)

	it("should yield correct Biber command", function()
		table.insert(mock_args.filelist, {path = "document.bcf", abspath = "./output/document.bcf"})

		local file = io.open("output/document.bcf", "w")
		assert(file)
		file:close()

		local co = coroutine.create(function()
			typeset_hooks.biber(mock_options, mock_args)
		end)
		local status, ret
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.truthy(ret:find("biber"))

		-- check if only yields one command
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.not_exist(ret)

		-- check if terminated
		status, ret = coroutine.resume(co)
		expect.falsy(status)
		expect.equal(ret, "cannot resume dead coroutine")
	end)

	it("should yield correct Memoize extraction command", function()
		table.insert(mock_args.filelist, {path = "document.mmz", abspath = "./output/document.mmz"})

		local file = io.open("output/document.mmz", "w")
		assert(file)
		file:write("\\mmzNewExtern")
		file:close()

		local co = coroutine.create(function()
			typeset_hooks.memoize_run(mock_options, mock_args)
		end)
		local status, ret
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.truthy(ret:find("memoize"))

		-- check if only yields one command
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.not_exist(ret)

		-- check if terminated
		status, ret = coroutine.resume(co)
		expect.falsy(status)
		expect.equal(ret, "cannot resume dead coroutine")
	end)

	it("should yield correct Sagetex command", function()
		table.insert(mock_args.filelist, {path = "document.sage", abspath = "./output/document.sage"})

		local file = io.open("output/document.sage", "w")
		assert(file)
		file:close()

		local co = coroutine.create(function()
			typeset_hooks.sagetex(mock_options, mock_args)
		end)
		local status, ret
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.truthy(ret:find("sage"))

		-- check if only yields one command
		status, ret = coroutine.resume(co)
		expect.truthy(status)
		expect.not_exist(ret)

		-- check if terminated
		status, ret = coroutine.resume(co)
		expect.falsy(status)
		expect.equal(ret, "cannot resume dead coroutine")
	end)
end)
