--[[
Copyright 2016 ARATA Mizuki
Copyright 2024 Lukas Heindl

This file is part of CluttealTeX.

CluttealTeX is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

CluttealTeX is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with CluttealTeX.  If not, see <http://www.gnu.org/licenses/>.
]]

local pathutil    = require "texrunner.pathutil"
local parseoption = require "texrunner.option".parseoption
local options     = require "texrunner.option_type"
local Option      = require "texrunner.option".Option
local TexEngine   = require "texrunner.tex_engine"
local message     = require "texrunner.message"
local fsutil      = require "texrunner.fsutil"
local option_spec = require "texrunner.option_spec".spec
local usage = require "texrunner.option_spec".usage

local record Module
	handle_cluttealtex_options: function({string}): string,TexEngine.Engine,options.Options
end

local KnownEngines = TexEngine.KnownEngines
global CLUTTEALTEX_VERSION:string

local record CfgOption
	options: {string:any}
	defaults: {string:string}
	-- of course the handle_cli function is not type checked this way
	add_cli_options: {string:table}
end

-- Default values for options
local function set_default_values(options:options.Options)
	if options.max_iterations == nil then
		options.max_iterations = 3
	end

	if options.skip_first == nil then
		options.skip_first = false
	end

	if options.interaction == nil then
		options.interaction = "nonstopmode"
	end

	if options.file_line_error == nil then
		options.file_line_error = true
	end

	if options.halt_on_error == nil then
		options.halt_on_error = true
	end

	if options.output_format == nil then
		options.output_format = "pdf"
	end
end

-- built up a lookup table over short and long options in order to speed up argument parsing
local option_spec_lut:{string:{any:string}} = {long={}, short={}}
for k,v in pairs(option_spec) do
	if v.long then
		option_spec_lut.long[v.long] = k
	end
	if v.short then
		option_spec_lut.short[v.short] = k
	end
end
local function query_long_options(name:string):Option,string,boolean
	local no = false
	local key = option_spec_lut.long[name]
	if not key then
		key = option_spec_lut.long["no-"..name]
		no = true
	end
	return option_spec[key], key, no
end
local function query_short_options(name:string):Option,string,boolean
	local key = option_spec_lut.short[name]
	return option_spec[key], key, false
end

local function merge_options(...: options.Options): options.Options
	local ret:{string:any} = {}
	for _, i in ipairs{...} do
		for k,v in pairs(i as {string:any}) do
			ret[k] = v
		end
	end
	return ret as options.Options
end


-- inputfile, engine, options = handle_cluttealtex_options(arg)
local function handle_cluttealtex_options(arg:{string}): string,TexEngine.Engine,options.Options
	-- Store options
	local var_options:{options.Options} = {
		-- place one dummy option record in the array to ensure these fields
		-- are defined as array even in case the user does not set these options
		{
			tex_extraoptions = {},
			dvipdfmx_extraoptions = {},
			package_support = {},
		}
	}
	local inputfile:string

		-- Parse options from config file
	if fsutil.isfile(".cluttealtexrc.lua") then
		local options:options.Options = {}
		-- see https://ref.coddy.tech/lua/lua-sandboxing
		-- for us the main purpose is to avoid the config modifies the
		-- environment we're working in.
		-- Apart from that restriction, the config is allowed to execute
		-- anything.
		-- local sandbox = {
		-- 	print   = print,
		-- 	-- Add other functions here
		-- }
		-- setmetatable(sandbox, {__index = function(t:table, k:any)
		-- 	return error("Forbidden function/variable", 2) -- TODO(cfg) deep-copy from _G on demand instead
		-- end})
		-- TODO(cfg) move to a lua file to make use of _G (dynamically copy over/return on __index)
		local cfgChunk, err = loadfile(".cluttealtexrc.lua")
		if err then
			message.error("Error loading the config file '.cluttealtexrc.lua'")
			error(err)
		end
		local cfg = (function(): CfgOption
			-- use a function for checking types of the config table
			local cfg: any
			cfg = cfgChunk()
			if not (cfg is table) or cfg is nil then
				message.error(".cluttealtexrc.lua needs to return a table with the configured options")
				os.exit(1)
			end
			local cfg = cfg as table

			local cfg_options = cfg.options
			if not (cfg_options is {string: any} or cfg_options is nil) then
				message.error(".cluttealtexrc.lua needs to return a table which contains an options key")
				os.exit(1)
			end

			local cfg_defaults = cfg.defaults
			if not (cfg_defaults is {string: string} or cfg_defaults is nil) then
				message.error(".cluttealtexrc.lua needs to return a table which contains an defaults key")
				os.exit(1)
			end

			local cfg_cli_options = cfg.cli_options
			if not (cfg_cli_options is {string: table} or cfg_cli_options is nil) then
				message.error(".cluttealtexrc.lua needs to return a table which contains an cli_options key")
				os.exit(1)
			end

			return {
					options=cfg_options as {string: any},
					defaults=cfg_defaults as {string: string},
					add_cli_options=cfg_cli_options as {string: table}
				}
		end)()

		-- print(cfg.options)
		-- print(cfg.defaults)
		-- print(cfg.add_cli_options) -- of course the handle_cli function is not type checked this way

		for optname, opt in pairs(cfg.options or {}) do
			if optname == "file" then
				assert(inputfile is nil, "multiple input files given")
				if not opt is string then
					message.error("parameter for 'file' must be a string in .cluttealtexrc.lua")
					os.exit(1)
				end
				inputfile = opt as string
			else
				-- if the option passed was a not a table, simply use the same handler like for cli arguments
				if option_spec[optname] then
					-- to avoid copying the following, wrap opt in a simple array in case the option does not accumulate
					-- to simplify passing a single value to an accumulating option, wrap the opt in that case as well
					if not option_spec[optname].accumulate then
						opt = {opt}
					elseif not opt is table then
						opt = {opt}
					end
					for _, opt in ipairs(opt as {any}) do
						if type(opt) == "string" then
							local o = option_spec[optname]
							if o.handle_cli then
								o.handle_cli(options, opt as string)
							else
								message.error(("%s needs to be set via a table in the config file"):format(optname))
								os.exit(1)
							end
						elseif type(opt) == "boolean" then
							if not option_spec[optname].boolean and option_spec[optname].default and (opt as boolean) then
								local o = assert(option_spec[optname])
								if o.handle_cli then
									o.handle_cli(options, option_spec[optname].default)
								else
									message.error(("%s needs to be set via a table in the config file"):format(optname))
									os.exit(1)
								end
							elseif option_spec[optname].boolean then
								local o = assert(option_spec[optname])
								if o.handle_cli then
									o.handle_cli(options, opt as boolean)
								else
									message.error(("%s needs to be set via a table in the config file"):format(optname))
									os.exit(1)
								end
							else
								message.error(("option %s does not take a boolean"):format(optname))
							end
						elseif type(opt) == "table" then
							if not option_spec[optname].handle_cfg then
								message.error(("config for '%s' must not be a table"):format(optname))
							else
								local o = assert(option_spec[optname])
								if o.handle_cli then
									o.handle_cfg(options, opt as table)
								else
									message.error(("%s needs to be set either as boolean/string in the config or as cli argument"):format(optname))
									os.exit(1)
								end
							end
						else
							message.error(("config for '%s' must be either string, boolean or table in .cluttealtexrc.lua"):format(optname))
							os.exit(1)
						end
					end
				else
					message.warn(("Option '%s' from .cluttealtexrc.lua unknown. Skipping that option"):format(optname))
				end
			end
		end

		for optname, default in pairs(cfg.defaults or {}) do
			if option_spec[optname] then
				option_spec[optname].default = default
			else
				message.warn(("Option '%s' from .cluttealtexrc.lua unknown. Not setting the default for this option"):format(optname))
			end
		end

		for optname, opt in pairs(cfg.add_cli_options or {}) do
			if option_spec[optname] then
				message.warn(("In .cluttealtexrc.lua you're trying to define an optname (%s) which is already defined -> skipping it"):format(optname))
			else
				if not opt.handle_cli or (not opt.long and not opt.short) then
					message.warn(("Options (%s) declared in .cluttealtexrc.lua must define the handle_cli function and at least have either long or short set -> skipping it"):format(optname))
				else
					option_spec[optname] = opt as Option
				end
			end
		end
		table.insert(var_options, options)
	end

	-- Parse options from commandline
	local option_and_params, non_option_index = parseoption(arg, query_long_options, query_short_options)

	-- Handle options
	do
		local options:options.Options = {}
		CLUTTEALTEX_VERBOSITY = 0
		for _,option in ipairs(option_and_params) do
			local optname:string = option[1]
			local param:string|boolean = option[2]
			local o = assert(option_spec[optname], "invalid optname found")
			if o.handle_cli then
				o.handle_cli(options, param)
			else
				message.error(("%s can only be set as a table via the config file"):format(optname))
				os.exit(1)
			end
		end
		table.insert(var_options, options)
	end

	local options = merge_options(table.unpack(var_options))

	if options.color == nil then
		message.set_colors("auto")
	end

	-- Handle non-options (i.e. input file)
	print(inputfile, non_option_index, #arg)
	if (inputfile and non_option_index <= #arg) or (not inputfile and non_option_index < #arg) then
		message.error("Multiple input files are not supported.")
		os.exit(1)
	elseif not inputfile and non_option_index > #arg then
		-- No input file given
		usage(arg)
		os.exit(1)
	elseif not inputfile then
		inputfile = arg[non_option_index]
	end

	-- TODO(refactor) remove
	-- If run as 'cllualatex', then the default engine is lualatex
	if options.engine == nil and type(arg[0]) == "string" then
		local basename = pathutil.trimext(pathutil.basename(arg[0]))
		local engine_part = string.match(basename, "^cl(%w+)$")
		if engine_part and KnownEngines[engine_part] then
			options.engine = engine_part
		end
	end

	if options.engine == nil then
		message.error("Engine not specified.")
		os.exit(1)
	end
	local engine = KnownEngines[options.engine]
	if not engine then
		message.error("Unknown engine name '", options.engine, "'.")
		os.exit(1)
	end

	set_default_values(options)

	-- parameter validy check TODO should this be organized as function like
	-- set_default_values and with a key in the option spec (list or function)?

	-- TODO(refactor) EDIT(lukas): no probably make use of the option_spec for
	-- this (add a new new function to which we pass the value set in the
	-- options table)
	if options.watch then
		if options.watch ~= "fswatch" and options.watch ~= "inotifywait" then
			message.error("Unknown wait engine '", options.watch, "'.")
			os.exit(1)
		end
	end

	if options.output_format == "pdf" then
		if options.check_driver ~= nil then
			error("--check-driver can only be used when the output format is DVI.")
		end
		if engine.supports_pdf_generation then
			if engine.is_luatex then
				options.check_driver = "luatex"
			elseif engine.name == "xetex" or engine.name == "xelatex" then
				options.check_driver = "xetex"
			elseif engine.name == "pdftex" or engine.name == "pdflatex" then
				options.check_driver = "pdftex"
			else
				message.warn("Unknown engine: "..engine.name)
				message.warn("Driver check will not work.")
			end
		else
			-- CluttealTeX uses dvipdfmx to generate PDF from DVI output.
			options.check_driver = "dvipdfmx"
		end
	end

	return inputfile, engine, options
end

local _M:Module = {
	handle_cluttealtex_options = handle_cluttealtex_options,
}
return _M
