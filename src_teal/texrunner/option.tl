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

local record Option
	short: string
	long: string
	param: boolean
	allow_single_hyphen: boolean
	default: string
	boolean: boolean
	accumulate: boolean
	handle_cli: function({string:any}, string|boolean)
	handle_cfg: function({string:any}, table)
end

local function parseoption(arg:{string}, query_long_options:(function(string):Option,string,boolean), query_short_options:(function(string):Option,string,boolean)): {{string,string|boolean}},integer
	local options_and_params:{{string,string|boolean}} = {}
	local i = 1

	while i <= #arg do
		local current = arg[i]

		if current == "--" then
			-- "--" marks the end of options
			-- TODO i += 1 ?
			break
		elseif current:sub(1, 2) == "--" then
			-- Long options (e.g., --option or --option=value)
			local option_name, value:string,string|boolean = current:match("^([^=]+)=(.*)$", 3)
			option_name = option_name or current:sub(3)

			local option, opt_name, no_opt = query_long_options(option_name)
			if not option then
				error("Unknown option: " .. option_name)
			end

			if option.param then
				if not value then
					value = arg[i + 1]
					if not value or value:sub(1, 1) == "-" then
						if option.default then
							value = option.default
						elseif option.boolean then
							value = not no_opt
						else
							error("Missing parameter for option: " .. opt_name)
						end
					else
						i = i + 1
					end
				end
				if option.boolean and not value is boolean then
					value = value == "true"
				end
				table.insert(options_and_params, { opt_name, value })
			else
				table.insert(options_and_params, { opt_name, not no_opt })
			end
			i = i + 1

		elseif current:sub(1, 1) == "-" then
			-- Short options or single-hyphen long options
			local option_name, value:string,string|boolean = current:match("^([^=]+)=(.*)$", 2)
			option_name = option_name or current:sub(2)

			local option, opt_name, no_opt:Option, string, boolean

			if #option_name == 1 then
				option, opt_name, no_opt = query_short_options(option_name)
			else
				option, opt_name, no_opt = query_long_options(option_name)
				if not option or not option.allow_single_hyphen then
					error("Unknown option: " .. option_name)
				end
			end
			if not option or not option.allow_single_hyphen then
				error("Unknown option: " .. option_name)
			end

			if option.param then
				if not value then
					value = arg[i + 1]
					if not value or value:sub(1, 1) == "-" then
						if option.default then
							value = option.default
						elseif option.boolean then
							value = not no_opt
						else
							error("Missing parameter for option: " .. opt_name)
						end
					else
						i = i + 1
					end
				end
				if option.boolean and not value is boolean then
					value = value == "true"
				end
				table.insert(options_and_params, { opt_name, value })
			else
				table.insert(options_and_params, { opt_name, not no_opt })
			end
			i = i + 1

		else
			-- Non-option argument, skip
			break
		end
	end

	-- Return the parsed options
	return options_and_params
end

return {
	parseoption = parseoption,
	Option      = Option,
}
