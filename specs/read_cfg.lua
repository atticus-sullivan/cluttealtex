local lfs = require 'lfs'
local lester = require 'lester'

local describe = lester.describe
local before   = lester.before
local after    = lester.after
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
CLUTTEALTEX_TEST_ENV  = true

local read_cfg = require 'src_lua.texrunner.read_cfg'.read_cfg

describe("read_cfg", function()
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

	local function write_config(filename, content)
		local file = io.open(filename, "w")
		assert(file)
		file:write(content)
		file:close()
	end

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

	it("should successfully execute a valid config file", function()
		local config_content = [[
			return { key = "value" }
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, {key="value"})
	end)

	it("should return an error for a non-existent file", function()
		local result = read_cfg("non_existent.lua")
		expect.truthy(result:match("Error loading the config file"))
	end)

	it("should prevent modification of globals", function()
		local config_content = [[
			_G.tampered = true
			return {}
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, {})
		expect.not_exist(_G.tampered)
	end)

	it("should isolate changes to the sandbox environment", function()
		local config_content = [[
			sandbox_variable = "test"
			return sandbox_variable
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, "test")
		expect.not_exist(_G.sandbox_variable)
	end)

	it("should handle syntax errors gracefully", function()
		local config_content = [[
			invalid lua syntax here
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.truthy(result:match("Error loading the config file"))
	end)

	it("should preserve the integrity of deeply nested global tables", function()
		_G.nested_table = { subtable = { key = "value" } }
		local config_content = [[
			nested_table.subtable.key = "tampered"
			return nested_table
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, {subtable={key="tampered"}})
		expect.equal(_G.nested_table, {subtable={key="value"}}) -- Ensure original is not tampered
	end)

	it("should execute a script with valid Lua functions", function()
		local config_content = [[
			local result = {}
			for i = 1, 5 do
				table.insert(result, i)
			end
			return result
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, {1,2,3,4,5})
	end)

	it("should execute scripts with metatables without tampering the global ones", function()
		_G.global_meta = {}
		setmetatable(_G.global_meta, { __index = function() return "default" end })

		local config_content = [[
			local meta = {}
			setmetatable(meta, { __index = function() return "sandboxed" end })
			return meta.key
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, "sandboxed")
		expect.equal(_G.global_meta.key, "default")
	end)

	it("should handle recursive tables in the global environment", function()
		local recursive_table = {}
		recursive_table.self = recursive_table
		_G.recursive_table = recursive_table

		local config_content = [[
			return recursive_table.self == recursive_table
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.truthy(result)
	end)

	it("should allow user-defined functions in the script", function()
		local config_content = [[
			local function add(a, b)
				return a + b
			end
			return add(2, 3)
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.equal(result, 5)
	end)

	it("should cleanly handle empty config files", function()
		write_config("empty_config.lua", "")

		local result = read_cfg("empty_config.lua")
		expect.not_exist(result)
	end)

	it("config should be able to make changes to tables passed as argument and return new tables", function()
		local x = {}
		local config_content = [[
			local function foo(tab)
				tab.key = "value"
				return {keyB="valueB"}
			end
			return foo
		]]
		write_config("config.lua", config_content)

		local result = read_cfg("config.lua")
		expect.exist(result)
		local y = result(x)
		expect.equal(x, {key="value"})
		expect.equal(y, {keyB="valueB"})
	end)
end)
