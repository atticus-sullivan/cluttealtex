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

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end

local option_t = require"texrunner.option_type"

local record Module
	parseoption: function(arg:{string}, query_long_options:(function(string):Option,string,boolean), query_short_options:(function(string):Option,string,boolean)): {{string,string|boolean}},integer
	_internal: internal
	record internal
		handle_option_param: function(option:Option, opt_name:string, no_opt:boolean, value:string|boolean, next_arg:string): {string,string|boolean},integer
	end
	record Option
		short:               string
		long:                string
		param:               boolean
		allow_single_hyphen: boolean
		default:             string
		boolean:             boolean
		accumulate:          boolean
		handle_cli:          function({string:any}, string|boolean)
		handle_cfg:          function({string:any}, table)
		no_cli:              boolean
		no_cfg:              boolean
		suggestion_handlers: SuggestionHandlers
		help:                Help
	end
	record Help
		param:    string
		text:     string
		longLine: boolean
		ordering: number
	end
	record SuggestionHandlers
		file_based:    function(option_t.Options)
		execlog_based: function(option_t.Options)
	end
end

-- Handles parsing an individual option, resolving its value if necessary
-- @param option:Option - The option metadata
-- @param opt_name:string - The resolved name of the option
-- @param no_opt:boolean - Indicates whether this is a negated option (e.g., "--no-<option>")
-- @param value:string|boolean - The value provided inline (if any)
-- @param next_arg:string - The next argument in the CLI input, potentially the value
-- @return {string, string|boolean}, integer - The parsed option and the number of additional arguments consumed
local function handle_option_param(option:Module.Option, opt_name:string, no_opt:boolean, value:string|boolean, next_arg:string): {string,string|boolean},integer
	local inc = 0
	if option.param then
		-- If the option requires a parameter, resolve its value
		if not value then
			value = next_arg -- Look at the next argument
			if not value or value:sub(1, 1) == "-" then
				-- next_arg can't be used as value
				if option.default then
					value = option.default
				elseif option.boolean then
					value = not no_opt
				else
					error("Missing parameter for option: " .. opt_name)
				end
			else
				-- next_arg is used as value
				inc = inc + 1
			end
		end
		if option.boolean and not value is boolean then
			-- Convert string values to boolean for boolean options
			value = value == "true"
		end
		return { opt_name, value }, inc
	else
		-- If the option doesn't take a parameter, treat it as a flag
		return { opt_name, not no_opt }, inc
	end
end

-- Parses command-line arguments into options and their associated values
-- @param arg:{string} - The list of command-line arguments
-- @param query_long_options:function - Callback to query metadata for long options
-- @param query_short_options:function - Callback to query metadata for short options
-- @return {{string,string|boolean}}, integer - A list of parsed options and their values
local function parseoption(arg:{string}, query_long_options:(function(string):Module.Option,string,boolean), query_short_options:(function(string):Module.Option,string,boolean)): {{string,string|boolean}},integer

	-- Stores the parsed options
	local options_and_params:{{string,string|boolean}} = {}
	-- Index for iterating over arguments
	local i = 1

	while i <= #arg do
		-- Current argument being processed
		local current = arg[i]

		if current == "--" then
			-- "--" marks the end of options; subsequent arguments are not parsed
			break
		elseif current:sub(1, 2) == "--" then
			-- Handles long options (e.g., --option or --option=value)
			local option_name, value:string,string|boolean = current:match("^([^=]+)=(.*)$", 3)
			-- Extract the option name
			option_name = option_name or current:sub(3)

			local option, opt_name, no_opt = query_long_options(option_name)
			if not option then
				error("Unknown option: " .. option_name)
			end

			-- Delegate parsing of the option's parameter/value
			local o, inc = handle_option_param(option, opt_name, no_opt, value, arg[i+1])
			-- Add the parsed option
			table.insert(options_and_params, o)
			-- Advance index by consumed arguments
			i = i + 1 + inc

		elseif current:sub(1, 1) == "-" then
			-- Handles short options or single-hyphen long options
			local option_name, value:string,string|boolean = current:match("^([^=]+)=(.*)$", 2)
			-- Extract the option name
			option_name = option_name or current:sub(2)

			local option, opt_name, no_opt:Module.Option, string, boolean

			if #option_name == 1 then
				-- Query as a short option
				option, opt_name, no_opt = query_short_options(option_name)
				if not option then
					error("Unknown option: " .. option_name)
				end
			else
				-- Query as a single-hyphen long option
				option, opt_name, no_opt = query_long_options(option_name)
				if not option or not option.allow_single_hyphen then
					error("Unknown option: " .. option_name)
				end
			end

			-- Delegate parsing of the option's parameter/value
			local o, inc = handle_option_param(option, opt_name, no_opt, value, arg[i+1])
			-- Add the parsed option
			table.insert(options_and_params, o)
			-- Advance index by consumed arguments
			i = i + 1 + inc

		else
			-- Non-option argument, skip
			break
		end
	end

	-- Return the parsed options
	return options_and_params, i
end

local _M:Module = {
	parseoption = parseoption,
}
if CLUTTEALTEX_TEST_ENV then
	_M._internal = {
		handle_option_param = handle_option_param,
	}
end
return _M
