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


-- inputfile, engine, options = handle_cluttealtex_options(arg)
local function handle_cluttealtex_options(arg:{string}): string,TexEngine.Engine,options.Options
	-- Store options
	local options:options.Options = {
		tex_extraoptions = {},
		dvipdfmx_extraoptions = {},
		package_support = {},
	}

	-- Parse options from commandline
	local option_and_params, non_option_index = parseoption(arg, query_long_options, query_short_options)

	-- Handle options
	CLUTTEALTEX_VERBOSITY = 0
	for _,option in ipairs(option_and_params) do
		local optname:string = option[1]
		local param:string|boolean = option[2]
		assert(option_spec[optname], "invalid optname found").handle_cli(options, param)
	end

	if options.color == nil then
		message.set_colors("auto")
	end

	-- Handle non-options (i.e. input file)
	if non_option_index > #arg then
		-- No input file given
		usage(arg)
		os.exit(1)
	elseif non_option_index < #arg then
		message.error("Multiple input files are not supported.")
		os.exit(1)
	end
	local inputfile = arg[non_option_index]

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
