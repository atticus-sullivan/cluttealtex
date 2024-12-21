--[[
  Copyright 2020 ARATA Mizuki
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
local assert = assert
local ipairs = ipairs
local pathutil = require "texrunner.pathutil"
local message = require "texrunner.message"
local reruncheck = require"texrunner.reruncheck"

-- Record definition for expected driver values
local record Values
	graphics: string -- Expected graphics driver (e.g., "dvips", "pdftex")
	expl3: EXPL3     -- Expected expl3 backend driver (old and new values supported)
	record EXPL3
		old: string  -- Old driver format
		new: string  -- New driver format
	end
	hyperref: string -- Expected hyperref driver
	xypic: string    -- Expected Xy-pic driver
end

-- Mapping of supported drivers and their corresponding expected values
local right_values:{string:Values} = {
	dvips = {
		graphics = "dvips",
		expl3    = {
			old = "dvips",
			new = "dvips",
		},
		hyperref = "dvips",
		xypic    = "dvips",
	},
	dvipdfmx = {
		graphics = "dvipdfmx",
		expl3    = {
			old = "dvipdfmx",
			new = "dvipdfmx",
		},
		hyperref = "dvipdfmx",
		xypic    = "pdf",
	},
	dvisvgm = {
		graphics = "dvisvgm",
		expl3    = {
			old = "dvisvgm",
			new = "dvisvgm",
		},
	},
	xetex = {
		graphics = "xetex",
		expl3    = {
			old = "xdvipdfmx",
			new = "xetex",
		},
		hyperref = "xetex",
		xypic    = "pdf",
	},
	pdftex = {
		graphics = "pdftex",
		expl3    = {
			old = "pdfmode",
			new = "pdftex",
		},
		hyperref = "pdftex",
		xypic    = "pdf",
	},
	luatex = {
		graphics = "luatex",
		expl3    = {
			old = "pdfmode",
			new = "luatex",
		},
		hyperref = "luatex",
		xypic    = "pdf",
	},
}

-- Generic function to detect a driver by matching loaded files with a mapping
local function detect_driver(loaded:{string:boolean}, mapping:{string:string}): string
	for file, driver in pairs(mapping) do
		if loaded[file] then return driver end
	end
	return "unknown" -- Return "unknown" if no match is found
end

-- Detect drivers for a specific subsystem
local function detect_graphics_driver(loaded: {string:boolean}): string
	if not (loaded["graphics.sty"] or loaded["color.sty"]) then
		-- Graphics subsystem not used
		return nil
	end
	return detect_driver(loaded, {
		["dvipdfmx.def"] = "dvipdfmx",
		["dvips.def"] = "dvips",
		["dvisvgm.def"] = "dvisvgm",
		["pdftex.def"] = "pdftex",
		["luatex.def"] = "luatex",
		["xetex.def"] = "xetex",
		-- Not supported: dvipdf, dvipsone, emtex, textures, pctexps, pctexwin, pctexhp, pctex32, truetex, tcidvi, vtex
	})
end

-- Detect drivers for the expl3 subsystem
local function detect_expl3_driver(loaded: {string:boolean}): string
	if not (loaded["expl3-code.tex"] or loaded["expl3.sty"] or loaded["l3backend-dvips.def"] or loaded["l3backend-dvipdfmx.def"] or loaded["l3backend-xdvipdfmx.def"] or loaded["l3backend-pdfmode.def"] or loaded["l3backend-pdftex.def"] or loaded["l3backend-luatex.def"] or loaded["l3backend-xetex.def"]) then
		-- expl3 subsystem not used
		return nil
	end
	return detect_driver(loaded, {
		["l3backend-pdfmode.def"] = "pdfmode",
		["l3backend-dvisvgm.def"] = "dvisvgm",
		["l3backend-xdvipdfmx.def"] = "xdvipdfmx",
		["l3backend-dvipdfmx.def"] = "dvipdfmx",
		["l3backend-dvips.def"] = "dvips",
		["l3backend-pdftex.def"] = "pdftex",
		["l3backend-luatex.def"] = "luatex",
		["l3backend-xetex.def"] = "xetex",
		-- TODO: driver=latex2e?
	})
end

-- Detect drivers for the hyperref package
local function detect_hyperref_driver(loaded: {string:boolean}): string
	if not (loaded["hyperref.sty"]) then
		-- Hyperref package not used
		return nil
	end
	return detect_driver(loaded, {
		["hluatex.def"] = "luatex",
		["hpdftex.def"] = "pdftex",
		["hxetex.def"] = "xetex",
		["hdvipdfm.def"] = "dvipdfmx",
		["hdvips.def"] = "dvips",
		-- Not supported: dvipson, dviwind, tex4ht, texture, vtex, vtexhtm, xtexmrk, hypertex
		-- TODO: dvisvgm?
	})
end

-- Detect drivers for the xy-pic package
local function detect_xypic_driver(loaded: {string:boolean}): string
	if not (loaded["xy.tex"]) then
		-- xy-pic package not used
		return nil
	end
	return detect_driver(loaded, {
		["xypdf.tex"] = "pdf", -- pdftex, luatex, xetex, dvipdfmx
		["xydvips.tex"] = "dvips",
		["hxetex.def"] = "xetex",
		["hdvipdfm.def"] = "dvipdfmx",
		["hdvips.def"] = "dvips",
		-- Not supported: dvidrv, dvitops, oztex, 17oztex, textures, 16textures, xdvi
		-- TODO: dvisvgm?
	})
end

-- Compare detected drivers with expected values and return a list of mismatches
local function get_driver_mismatches(loaded: {string:boolean}, expected: Values): {string}
	local mismatches = {}
	local graphics_driver = detect_graphics_driver(loaded)
	if graphics_driver and expected.graphics and graphics_driver ~= expected.graphics then
		table.insert(mismatches, "graphics")
	end

	local expl3_driver = detect_expl3_driver(loaded)
	if expl3_driver and expected.expl3 and expl3_driver ~= expected.expl3.old and expl3_driver ~= expected.expl3.new then
		table.insert(mismatches, "expl3")
	end

	local hyperref_driver = detect_hyperref_driver(loaded)
	if hyperref_driver and expected.hyperref and hyperref_driver ~= expected.hyperref then
		table.insert(mismatches, "hyperref")
	end


	local xypic_driver = detect_xypic_driver(loaded)
	if xypic_driver and expected.xypic and xypic_driver ~= expected.xypic then
		table.insert(mismatches, "xypic")
	end

	-- Verbose logging of detected drivers
	if CLUTTEALTEX_VERBOSITY >= 1 then
		message.info("checkdriver: graphics=", tostring(graphics_driver))
		message.info("checkdriver: expl3=", tostring(expl3_driver))
		message.info("checkdriver: hyperref=", tostring(hyperref_driver))
		message.info("checkdriver: xypic=", tostring(xypic_driver))
	end

	return mismatches
end

-- Diagnostic output for driver mismatches
local mismatch_output:{string:function} = {
	graphics = function(expected:Values, _:string)
		message.diag("The driver option for graphics(x)/color is missing or wrong.")
		message.diag("Consider setting '", expected.graphics, "' option.")
	end,
	expl3 = function(expected:Values, _:string)
		message.diag("The driver option for expl3 is missing or wrong.")
		message.diag("Consider setting 'driver=", expected.expl3.new, "' option when loading expl3.")
		if expected.expl3.old ~= expected.expl3.new then
			message.diag("You might need to instead set 'driver=", expected.expl3.old, "' if you are using an older version of expl3.")
		end
	end,
	hyperref = function(expected:Values, _:string)
		message.diag("The driver option for hyperref is missing or wrong.")
		message.diag("Consider setting '", expected.hyperref, "' option.")
	end,
	xypic = function(expected:Values, expected_driver:string)
		message.diag("The driver option for Xy-pic is missing or wrong.")
		if expected_driver == "dvipdfmx" then
			message.diag("Consider setting 'dvipdfmx' option or running \\xyoption{pdf}.")
			elseif expected_driver == "pdftex" then
			message.diag("Consider setting 'pdftex' option or running \\xyoption{pdf}.")
			elseif expected.xypic == "pdf" then
			message.diag("Consider setting 'pdf' package option or running \\xyoption{pdf}.")
			elseif expected.xypic == "dvips" then
			message.diag("Consider setting 'dvips' option.")
		end
	end,
}

-- Main function to check drivers based on expected driver and loaded files
-- @param expected_driver: one of "dvips", "dvipdfmx", "dvisvgm", "pdftex", "xetex", "luatex"
local function checkdriver(expected_driver: string, filelist: {reruncheck.Filemap_ele}): {string}
	if CLUTTEALTEX_VERBOSITY >= 1 then
		message.info("checkdriver: expects ", expected_driver)
	end

	-- Gather loaded files into a table
	local loaded = {}
	for _, t in ipairs(filelist) do
		if t.kind == "input" then
			local basename = pathutil.basename(t.path)
			loaded[basename] = true
		end
	end

	-- Validate expected driver
	local expected = assert(right_values[expected_driver], "invalid value for expected_driver")

	-- Get mismatches and output diagnostics
	local mismatches = get_driver_mismatches(loaded, expected)
	if #mismatches > 0 then
		if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("checkdriver: mismatches found in ", table.concat(mismatches, ", "))
		end

		for _, mismatch in ipairs(mismatches) do
		mismatch_output[mismatch](expected, expected_driver)
	end
		else
		if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("checkdriver: all drivers matched as expected")
		end
	end
	return mismatches
end

return {
	checkdriver = checkdriver,
}
