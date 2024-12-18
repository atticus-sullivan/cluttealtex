--[[
  Copyright 2018 ARATA Mizuki
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

local function deep_copy(x)
	if type(x) == "table" then
		local r = {}
		for k,v in pairs(x) do
			r[k] = deep_copy(v)
		end
		return r
	else
		return x
	end
end

-- safely read the file at path as config file
-- Goal: Run config file without imposing restrictions to the config file
-- (it is allowed to contain any code). But guard the global environment
-- from being modified by the config file.
--
-- In order to do this, when the there is an access to the global environment,
-- the required part of the environment is (deep) copied over to the environment
-- of the config file on demand.
-- Of course this might consume some memory, but usually the global environment
-- is not that large and also there should only be one config that is read on
-- startup.
--
-- Note: This does not ensure confidentiality, only integrity
--
-- Concept from https://ref.coddy.tech/lua/lua-sandboxing
local function read_cfg(path)
	local sandbox = {}
	setmetatable(sandbox, {__index = function(t, k)
		if _G[k] then
			t[k] = deep_copy(_G[k])
			return t[k]
		end
		return nil
	end})

	local cfgChunk, err = loadfile(path, "t", sandbox)
	if not cfgChunk or err then
		return "Error loading the config file '.cluttealtexrc.lua': "..(err or "")
	end
	return cfgChunk()
end

return {
	read_cfg = read_cfg,
}
