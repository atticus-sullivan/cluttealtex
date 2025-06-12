-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local function deep_copy(x, seen)
	seen = seen or {}
	if type(x) == "table" then
		if seen[x] then return seen[x] end
		local r = {}
		seen[x] = r
		for k,v in pairs(x) do
			r[deep_copy(k, seen)] = deep_copy(v, seen)
		end
		return setmetatable(r, getmetatable(x))
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
