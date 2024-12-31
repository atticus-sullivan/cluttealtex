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
local init_hooks  = require "texrunner.option_spec".init_hooks
local usage = require "texrunner.option_spec".usage
local read_cfg = require "texrunner.read_cfg".read_cfg

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end

-- List of known TeX engines
local KnownEngines = TexEngine.KnownEngines

-- Record type to hold the structure for configuration options obtained from the config file
local record CfgOption
	options: {string:any}
	defaults: {string:string}
	-- of course the handle_cli function is not type checked this way
	add_cli_options: {string:table}
end

-- Create a lookup table for faster option parsing by short and long names
local option_spec_lut:{string:{any:string}} = {long={}, short={}}

local function build_lut()
	option_spec_lut = {long={}, short={}}
	for k,v in pairs(option_spec) do
		if v.long then
			-- Lookup for long options
			option_spec_lut.long[v.long] = k
		end
		if v.short then
			-- Lookup for short options
			option_spec_lut.short[v.short] = k
		end
	end
end
build_lut()

-- Function to query an option by its name (either long or short form)
local function query_options(name:string, kind:string): Option,string,boolean
	-- Look up the option
	local key = option_spec_lut[kind][name]
	-- Flag to check for negated options (e.g., --no-option)
	local no = false
	if not key and kind == "long" then
		-- Check for negated long options
		key = option_spec_lut.long["no-"..name]
		no = true
	end
	-- Return the option, its key, and the negation flag
	return option_spec[key], key, no
end

local function merge_hook_type(ht:string, hs:{number:any}, ret:{string:any})
	local hooks = ret["hooks"] as {string:{number:any}}
	if ht:find("^suggestion") then
		-- hooks are enabled by default
		-- disable hooks not set in the next options
		for k,_ in pairs(hooks[ht]) do
			if not hs[k] then
				hooks[ht][k] = nil
			end
		end
	else
		-- hooks are disabled by default
		-- enable hooks set in the next options
		for k,v in pairs(hs) do
			hooks[ht][k] = v
		end
	end
end

-- Function to merge multiple option tables into one
-- first table has highest priority etc.
local function merge_options(...: options.Options): options.Options
	-- Table to hold merged options
	local ret:{string:any} = {}
	local first = true
	-- Iterate over each passed options table
	for _, i in ipairs{...} do
		for k,v in pairs(i as {string:any}) do
			if k == "hooks" and not first then
				-- hooks need t be handled specially
				for ht, hs in pairs(v as {string:{number:any}}) do
					merge_hook_type(ht, hs, ret)
				end
			else
				-- Add each option from the table to the result
				ret[k] = v
			end
		end
		first = false
	end
	-- Return the merged options table
	return ret as options.Options
end

-- Function to handle boolean options (i.e., options that are true or false)
local function handle_boolean_option(o: Option, optname: string, options: {string: any}, value: boolean)
	if not o.boolean and o.default and value then
		-- If the option is not boolean but has a default value, set it via cli/cfg handler
		if o.handle_cli then
			local def = o.default
			o.handle_cli(options, def)
		else
			message.error(("%s needs to be set via a table in the config file"):format(optname))
			exit(1)
		end
	elseif o.boolean then
		-- If the option is a boolean, handle it via cli handler
		if o.handle_cli then
			o.handle_cli(options, value)
		else
			message.error(("%s needs to be set via a table in the config file"):format(optname))
			exit(1)
		end
	else
		message.error(("option %s does not take a boolean"):format(optname))
		exit(1)
	end
end

-- Function to handle table options (options that take a table as value)
local function handle_table_option(o: Option, optname: string, options: {string: any}, value: table)
	if o.handle_cfg then
		-- If the option has a configuration handler, pass the table to it
		o.handle_cfg(options, value)
	elseif o.handle_cli then
		-- If handled via CLI, throw an error (table not allowed in config)
		message.error(("config for '%s' must not be a table in .cluttealtexrc.lua"):format(optname))
		exit(1)
	else
		message.error(("config for '%s' is not handled at all"):format(optname))
		exit(1)
	end
end

-- Function to handle configuration options from the .cluttealtexrc.lua file
local function handle_config_option(optname: string, opt: any, options: {string: any})
	if option_spec[optname] then
		local o = option_spec[optname]
		if o.no_cfg then
			message.error(("%s no valid option in config file"):format(optname))
			exit(1)
		end
		if not o.accumulate then
			-- If option doesn't accumulate, wrap it in an array for uniform processing
			opt = {opt}
		elseif not opt is table then
			-- If accumulating option is not a table, wrap it in a table
			opt = {opt}
		end

		for _, value in ipairs(opt as {any}) do
			if value is string then
				-- Handle string values
				if o.handle_cli then
					o.handle_cli(options, value)
				else
					message.error(("%s needs to be set via a table in the config file"):format(optname))
					exit(1)
				end
			elseif value is boolean then
				-- Handle boolean values
				handle_boolean_option(o, optname, options, value)
			elseif value is table then
				-- Handle table values
				handle_table_option(o, optname, options, value)
			else
				message.error(("config for '%s' must be either string, boolean or table in .cluttealtexrc.lua"):format(optname))
				exit(1)
			end
		end
	else
		message.warn(("Option '%s' from .cluttealtexrc.lua unknown. Skipping that option"):format(optname))
	end
end

-- Function to handle setting default values for options from .cluttealtexrc.lua
local function handle_config_defaults(defaults: {string: string})
	for optname, default in pairs(defaults) do
		if option_spec[optname] then
			-- Set default if option exists
			option_spec[optname].default = default
		else
			message.warn(("Option '%s' from .cluttealtexrc.lua unknown. Not setting the default for this option"):format(optname))
		end
	end
end

-- Function to handle adding custom CLI options from the config file
local function add_custom_cli_options(add_cli_options: {string: table})
	for optname, opt in pairs(add_cli_options) do
		if option_spec[optname] then
			message.warn(("In .cluttealtexrc.lua you're trying to define an optname (%s) which is already defined -> skipping it"):format(optname))
		else
			if not opt.handle_cli or (not opt.long and not opt.short) then
				-- Custom options must have a handler and at least one identifier (long or short form)
				message.warn(("Options (%s) declared in .cluttealtexrc.lua must define the handle_cli function and at least have either long or short set -> skipping it"):format(optname))
			else
				-- Add the custom option to the spec
				option_spec[optname] = opt as Option
			end
		end
	end
	build_lut()
end

-- Function to parse the configuration file .cluttealtexrc.lua
local function parse_config_file(): options.Options, string
	local options:options.Options = {}
	local inputfile:string
	if fsutil.isfile(".cluttealtexrc.lua") then
		local cfg = (function(): CfgOption
			-- Read and validate the config file
			local cfg_raw, err = read_cfg(".cluttealtexrc.lua")
			if err or not cfg_raw then
				message.error("Error during reading the .cluttealtexrc.lua file: " .. (err or ""))
				exit(1)
			end
			if not (cfg_raw is table) or cfg_raw is nil then
				message.error(".cluttealtexrc.lua needs to return a table with the configured options")
				exit(1)
			end
			local cfg = cfg_raw as table

			local cfg_options = cfg.options
			if not (cfg_options is {string: any} or cfg_options is nil) then
				message.error(".cluttealtexrc.lua needs to return a table which contains an options key")
				exit(1)
			end

			local cfg_defaults = cfg.defaults
			if not (cfg_defaults is {string: string} or cfg_defaults is nil) then
				message.error(".cluttealtexrc.lua needs to return a table which contains an defaults key")
				exit(1)
			end

			local cfg_cli_options = cfg.cli_options
			if not (cfg_cli_options is {string: table} or cfg_cli_options is nil) then
				message.error(".cluttealtexrc.lua needs to return a table which contains an cli_options key")
				exit(1)
			end

			return {
					options=cfg_options as {string: any},
					defaults=cfg_defaults as {string: string},
					add_cli_options=cfg_cli_options as {string: table}
				}
		end)()

		-- Process the options key in the config
		for optname, opt in pairs(cfg.options or {}) do
			if optname == "file" then
				assert(inputfile is nil, "multiple input files given")
				inputfile = opt as string
			else
				handle_config_option(optname, opt, options)
			end
		end

		-- Process default options
		handle_config_defaults(cfg.defaults or {})

		-- Process additional CLI options
		add_custom_cli_options(cfg.add_cli_options or {})
	end
	return options, inputfile
end

-- Function to parse command-line options
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
		if not o.no_cli then
			if o.handle_cli then
				-- Handle each option via the appropriate handler
				o.handle_cli(options, param)
			else
				message.error(("%s can only be set as a table via the config file"):format(optname))
				exit(1)
			end
		else
			message.error(("%s no valid option via cli"):format(optname))
			exit(1)
		end
	end
	-- Return the parsed options and non-option index
	return options, non_option_index
end

-- Function to handle input files (ensures only one is provided)
local function handle_input_file(arg: {string}, inputfile: string, non_option_index: integer): string
	if (inputfile and non_option_index <= #arg) or (not inputfile and non_option_index < #arg) then
		message.error("Multiple input files are not supported.")
		exit(1)
	elseif not inputfile and non_option_index > #arg then
		-- No input file given
		usage(arg)
		exit(1)
	elseif not inputfile then
		-- Assign the input file
		inputfile = arg[non_option_index]
	end
	return inputfile
end

-- Function to determine the TeX engine to use based on options or input file
-- TODO(refactor) remove
-- If run as 'cllualatex', then the default engine is lualatex
local function determine_engine(options: options.Options, arg: {string}): TexEngine.Engine
	if options.engine == nil and type(arg[0]) == "string" then
		-- If engine is not specified, infer it from the input file
		local basename = pathutil.trimext(pathutil.basename(arg[0]))
		local engine_part = string.match(basename, "^cl(%w+)$")
		if engine_part and KnownEngines[engine_part] then
			options.engine = engine_part
		end
	end

	if options.engine == nil then
		-- Error if engine is still not determined
		message.error("Engine not specified.")
		exit(1)
	end

	local engine = KnownEngines[options.engine]
	if not engine then
		-- Handle unknown engine
		message.error("Unknown engine name '", options.engine, "'.")
		exit(1)
	end

	-- Return the engine object
	return engine
end

-- Main function to handle all options and configuration
local function handle_cluttealtex_options(arg: {string}): string, TexEngine.Engine, options.Options
	-- Define default options
	local default_options:options.Options = {
			-- important default values because these options need to be tables
			-- (otherwise iterating over them fails)
			tex_extraoptions      = {},
			dvipdfmx_extraoptions = {},
			package_support       = {},
			-- ordinary default values
			max_iterations        = 3,
			skip_first            = false,
			interaction           = "nonstopmode",
			file_line_error       = true,
			halt_on_error         = true,
			output_format         = "pdf",
	}
	init_hooks(default_options)

	-- Parse configuration and command-line options
	local config_options, inputfile = parse_config_file()
	local cli_options, non_option_index = parse_command_line_options(arg)

	-- Merge options from all sources (default, config, CLI)
	local options = merge_options(default_options, config_options, cli_options)

	-- Set default color handling if not set
	if options.color == nil then
		message.set_colors("auto")
	end

	-- Handle the input file (check and assign)
	inputfile = handle_input_file(arg, inputfile, non_option_index)

	-- Determine the TeX engine to use based on the options or input
	local engine = determine_engine(options, arg)

	-- TODO: Add validation logic here
	-- better: move validationlogic to option_spec
	if options.watch then
		if options.watch ~= "fswatch" and options.watch ~= "inotifywait" then
			message.error("Unknown wait engine '", options.watch, "'.")
			exit(1)
		end
	end

	if options.output_format == "pdf" then
		if options.check_driver ~= nil then
			message.error("--check-driver can only be used when the output format is DVI.")
			exit(1)
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

	-- Return the processed options
	return inputfile, engine, options
end

local record Module
	handle_cluttealtex_options: function({string}): string,TexEngine.Engine,options.Options
	_internal: internal
	record internal
		add_custom_cli_options:     function(add_cli_options: {string: table})
		determine_engine:           function(options: options.Options, arg: {string}): TexEngine.Engine
		handle_boolean_option:      function(o: Option, optname: string, options: {string: any}, value: boolean)
		handle_config_defaults:     function(defaults: {string: string})
		handle_config_option:       function(optname: string, opt: any, options: {string: any})
		handle_input_file:          function(arg: {string}, inputfile: string, non_option_index: integer): string
		handle_table_option:        function(o: Option, optname: string, options: {string: any}, value: table)
		merge_options:              function(...: options.Options): options.Options
		parse_command_line_options: function(arg: {string}): options.Options, integer
		parse_config_file:          function(): options.Options, string
		query_options:              function(name:string, kind:string): Option,string,boolean
	end
end

local _M:Module = {
	handle_cluttealtex_options = handle_cluttealtex_options,
}
if CLUTTEALTEX_TEST_ENV then
	_M._internal = {
		add_custom_cli_options     = add_custom_cli_options,
		determine_engine           = determine_engine,
		handle_boolean_option      = handle_boolean_option,
		handle_config_defaults     = handle_config_defaults,
		handle_config_option       = handle_config_option,
		handle_input_file          = handle_input_file,
		handle_table_option        = handle_table_option,
		merge_options              = merge_options,
		parse_command_line_options = parse_command_line_options,
		parse_config_file          = parse_config_file,
		query_options              = query_options,
	}
end
return _M
