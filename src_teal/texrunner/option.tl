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
end

-- options_and_params, i = parseoption(arg, options)
-- options[i] = {short = "o", long = "option" [, param = true] [, boolean = true] [, allow_single_hyphen = false]}
-- options_and_params[j] = {"option", "value"}
-- arg[i], arg[i + 1], ..., arg[#arg] are non-options
local function parseoption(arg:{string}, options:{Option}): {{string,string|boolean}},integer
local i = 1
	local option_and_params:{{string,string|boolean}} = {}
	while i <= #arg do
		if arg[i] == "--" then
			-- Stop handling options
			i = i + 1
			break
		elseif arg[i]:sub(1,2) == "--" then
			-- Long option
			local param:string|boolean
			local name:string
			name,param = arg[i]:match("^([^=]+)=(.*)$", 3)
			name = name or arg[i]:sub(3)
			local opt:Option = nil
			for _,o in ipairs(options) do
				if o.long then
					if o.long == name then
						if o.param then
							if param then
								-- --option=param
							else
								if o.default ~= nil then
									param = o.default
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
						opt = o
						break
					elseif o.boolean and name == "no-" .. o.long then
						-- --no-option
						opt = o
						param = false
						break
					end
				end
			end
			if opt then
				table.insert(option_and_params, {opt.long, param})
			else
				-- Unknown long option
				error("unknown long option: " .. arg[i])
			end
		elseif arg[i]:sub(1,1) == "-" then
			local param:string|boolean
			local name:string
			name,param = arg[i]:match("^([^=]+)=(.*)$", 2)
			name = name or arg[i]:sub(2)
			local opt:Option = nil
			for _,o in ipairs(options) do
				if o.long and o.allow_single_hyphen then
					if o.long == name then
						if o.param then
							if param then
								-- -option=param
							else
								if o.default ~= nil then
									param = o.default
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
						opt = o
						break
					elseif o.boolean and name == "no-" .. o.long then
						-- -no-option
						opt = o
						param = false
						break
					end
				elseif o.long and #name >= 2 and (o.long == name or (o.boolean and name == "no-" .. o.long)) then
					error("You must supply two hyphens (i.e. --" .. name .. ") for long option")
				end
			end
			if opt == nil then
				-- Short option
				name = arg[i]:sub(2,2)
				for _,o in ipairs(options) do
					if o.short then
						if o.short == name then
							if o.param then
								if #arg[i] > 2 then
									-- -oparam
									param = arg[i]:sub(3)
								else
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
							opt = o
							break
						end
					end
				end
			end
			if opt then
				table.insert(option_and_params, {opt.long or opt.short, param})
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
	parseoption = parseoption;
}
