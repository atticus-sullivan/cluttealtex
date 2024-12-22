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
local read_cfg = require "texrunner.read_cfg".read_cfg

local record Module
	handle_cluttealtex_options: function({string}): string,TexEngine.Engine,options.Options
end

local KnownEngines = TexEngine.KnownEngines

local record CfgOption
	options: {string:any}
	defaults: {string:string}
	-- of course the handle_cli function is not type checked this way
	add_cli_options: {string:table}
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

local function query_options(name:string, kind:string): Option,string,boolean
	local key = option_spec_lut[kind][name]
	local no = false
	if not key and kind == "long" then
		key = option_spec_lut.long["no-"..name]
		no = true
	end
	return option_spec[key], key, no
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

local function handle_boolean_option(o: Option, optname: string, options: {string: any}, value: boolean)
	if not o.boolean and o.default and value then
		if o.handle_cli then
			o.handle_cli(options, o.default)
		else
			message.error(("%s needs to be set via a table in the config file"):format(optname))
			os.exit(1)
		end
	elseif o.boolean then
		if o.handle_cli then
			o.handle_cli(options, value)
		else
			message.error(("%s needs to be set via a table in the config file"):format(optname))
			os.exit(1)
		end
	else
		message.error(("option %s does not take a boolean"):format(optname))
	end
end

local function handle_table_option(o: Option, optname: string, options: {string: any}, value: table)
	if o.handle_cfg then
		o.handle_cfg(options, value)
	elseif o.handle_cli then
		message.error(("config for '%s' must not be a table in .cluttealtexrc.lua"):format(optname))
		os.exit(1)
	end
end

local function handle_config_option(optname: string, opt: any, options: {string: any})
	if option_spec[optname] then
		local o = option_spec[optname]
		if not o.accumulate then
			-- if option is not accumulating, wrap it in an array to be able to
			-- use the same processing code like with accumulating options
			opt = {opt}
		elseif not opt is table then
			-- if option is accumulating, but wasn't passed a table, simply
			-- wrap it in a table to simplify the config file
			opt = {opt}
		end

		for _, value in ipairs(opt as {any}) do
			if value is string then
				if o.handle_cli then
					o.handle_cli(options, value)
				else
					message.error(("%s needs to be set via a table in the config file"):format(optname))
					os.exit(1)
				end
			elseif value is boolean then
				handle_boolean_option(o, optname, options, value)
			elseif value is table then
				handle_table_option(o, optname, options, value)
			else
				message.error(("config for '%s' must be either string, boolean or table in .cluttealtexrc.lua"):format(optname))
				os.exit(1)
			end
		end
	else
		message.warn(("Option '%s' from .cluttealtexrc.lua unknown. Skipping that option"):format(optname))
	end
end

local function handle_config_defaults(defaults: {string: string})
	for optname, default in pairs(defaults) do
		if option_spec[optname] then
			option_spec[optname].default = default
		else
			message.warn(("Option '%s' from .cluttealtexrc.lua unknown. Not setting the default for this option"):format(optname))
		end
	end
end

local function add_custom_cli_options(add_cli_options: {string: table})
	for optname, opt in pairs(add_cli_options) do
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
end

local function parse_config_file(): options.Options, string
	local options:options.Options = {}
	local inputfile:string
	if fsutil.isfile(".cluttealtexrc.lua") then
		local cfg = (function(): CfgOption
			-- use a function for checking types of the config table
			local cfg_raw, err = read_cfg(".cluttealtexrc.lua")
			if err or not cfg_raw then
				message.error("Error during reading the .cluttealtexrc.lua file: " .. (err or ""))
				os.exit(1)
			end
			if not (cfg_raw is table) or cfg_raw is nil then
				message.error(".cluttealtexrc.lua needs to return a table with the configured options")
				os.exit(1)
			end
			local cfg = cfg_raw as table

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

		-- process options key
		for optname, opt in pairs(cfg.options or {}) do
			if optname == "file" then
				assert(inputfile is nil, "multiple input files given")
				inputfile = opt as string
			else
				handle_config_option(optname, opt, options)
			end
		end

		-- process defaults key
		handle_config_defaults(cfg.defaults or {})

		-- process add_cli_options key
		add_custom_cli_options(cfg.add_cli_options or {})
	end
	return options, inputfile
end

local function parse_command_line_options(arg: {string}): options.Options, integer
	local option_and_params, non_option_index = parseoption(
		arg,
		function(name: string): Option, string, boolean return query_options(name, "long") end,
		function(name: string): Option, string, boolean return query_options(name, "short") end
	)
	local options:options.Options = {}
	CLUTTEALTEX_VERBOSITY = 0
	for _, option in ipairs(option_and_params) do
		local optname:string       = option[1]
		local param:string|boolean = option[2]
		local o = assert(option_spec[optname], "invalid optname found")
		if o.handle_cli then
			o.handle_cli(options, param)
		else
			message.error(("%s can only be set as a table via the config file"):format(optname))
			os.exit(1)
		end
	end
	return options, non_option_index
end

local function handle_input_file(arg: {string}, inputfile: string, non_option_index: integer): string
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
	return inputfile
end

-- TODO(refactor) remove
-- If run as 'cllualatex', then the default engine is lualatex
local function determine_engine(options: options.Options, arg: {string}): TexEngine.Engine
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

	return engine
end

local function handle_cluttealtex_options(arg: {string}): string, TexEngine.Engine, options.Options
	local default_options:options.Options = {
			tex_extraoptions = {},
			dvipdfmx_extraoptions = {},
			package_support = {},
			-- ordinary default values
			max_iterations = 3,
			skip_first = false,
			interaction = "nonstopmode",
			file_line_error = true,
			halt_on_error = true,
			output_format = "pdf",
	}

	local config_options, inputfile = parse_config_file()
	local cli_options, non_option_index = parse_command_line_options(arg)
	local options = merge_options(default_options, config_options, cli_options)

	if options.color == nil then
		message.set_colors("auto")
	end

	inputfile = handle_input_file(arg, inputfile, non_option_index)
	local engine = determine_engine(options, arg)

	-- TODO: Add validation logic here
	-- better: move validationlogic to option_spec
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
