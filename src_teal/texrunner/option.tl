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

-- options_and_params, i = parseoption(arg, options)
-- options[i] = {short = "o", long = "option" [, param = true] [, boolean = true] [, allow_single_hyphen = false]}
-- options_and_params[j] = {"option", "value"}
-- arg[i], arg[i + 1], ..., arg[#arg] are non-options
local function parseoption(arg:{string}, query_long_options:(function(string):Option,string,boolean), query_short_options:(function(string):Option,string,boolean)): {{string,string|boolean}},integer
local i = 1
	local option_and_params:{{string,string|boolean}} = {}
	while i <= #arg do
		if arg[i] == "--" then
			-- Stop handling options
			i = i + 1
			break
		elseif arg[i]:sub(1,2) == "--" then
			-- two hypens
			local param:string|boolean
			local name:string
			name,param = arg[i]:match("^([^=]+)=(.*)$", 3)
			name = name or arg[i]:sub(3)
			local opt, optname, no_opt = query_long_options(name)
			if opt and opt.long then
				-- option was found as long option with two hypens
				if not no_opt then
					-- option is "normal" (no 'no-' prefix)
					-- check if option takes an argument
					if opt.param then
						if param then
							-- --option=param
						else
							if opt.default ~= nil then
								-- no param with space if option specifies a
								-- default in order to avoid accidentally
								-- consuming the next argument
								param = opt.default
							else
								-- --option param
								assert(i + 1 <= #arg, "argument missing after " .. arg[i] .. " option")
								param = arg[i + 1]
								i = i + 1
							end
						end
					else
						-- --option
						param = true
					end
				elseif opt.boolean and no_opt then
					-- --no-option
					param = false
				else
					error("no- option can't have a value assigned to it")
				end
				table.insert(option_and_params, {optname, param})
			else
				-- Unknown long option
				error("unknown long option: " .. arg[i])
			end

		elseif arg[i]:sub(1,1) == "-" then
			-- one hypen
			local param:string|boolean
			local name:string
			name,param = arg[i]:match("^([^=]+)=(.*)$", 2)
			name = name or arg[i]:sub(2)
			local opt, optname, no_opt = query_long_options(name)
			if opt and opt.long and opt.allow_single_hyphen then
				if not no_opt then
					if opt.param then
						if param then
							-- -option=param
						else
							if opt.default ~= nil then
								-- no param with space if option specifies a
								-- default in order to avoid accidentally
								-- consuming the next argument
								param = opt.default
							else
								-- -option param
								assert(i + 1 <= #arg, "argument missing after " .. arg[i] .. " option")
								param = arg[i + 1]
								i = i + 1
							end
						end
					else
						-- -option
						param = true
					end
				elseif opt.boolean and no_opt then
					-- -no-option
					param = false
				else
					error("no- option can't have a value assigned to it")
				end
			elseif opt and opt.long and #name >= 2 then
				error("You must supply two hyphens (i.e. --" .. name .. ") for long option")
			end

			-- parse as short option if not able to parse as long option with one hypen
			if opt == nil then
				-- Short option
				name = arg[i]:sub(2,2)
				opt, optname = query_short_options(name)
				if opt and opt.short then
					-- option was found as short option
					if opt.param then
						if #arg[i] > 2 then
							-- -oparam
							param = arg[i]:sub(3)
						else
						-- passing arguments separated with space is common with short options
						-- -> no default here TODO not a nice consistent behavior
							-- -o param
							assert(i + 1 <= #arg, "argument missing after " .. arg[i] .. " option")
							param = arg[i + 1]
							i = i + 1
						end
					else
						-- -o
						assert(#arg[i] == 2, "combining multiple short options like -abc is not supported")
						param = true
					end
				end
			end
			if opt then
				table.insert(option_and_params, {optname, param})
			else
				error("unknown short option: " .. arg[i])
			end
		else
			-- arg[i] is not an option
			break
		end
		i = i + 1
	end
	return option_and_params, i
end

return {
	parseoption = parseoption,
	Option      = Option,
}
