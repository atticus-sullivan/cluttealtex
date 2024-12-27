--[[
  Copyright 2016,2019 ARATA Mizuki
  Copyright 2024 Lukas Heindl

  This file is part of CluttealTeX.

  ClutTeXteal is free software: you can redistribute it and/or modify
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

local table = table
local setmetatable = setmetatable
local ipairs = ipairs

local shellutil  = require "texrunner.shellutil"
local luatexinit = require "texrunner.luatexinit"
local Module     = require "texrunner.tex_engine_t"

-- Default metadata for engines, with a default DVI extension
local meta: Module.Engine = {dvi_extension = "dvi"}
-- Default metadata for engines, with a default DVI extension
local engine_meta:metatable<Module.Engine> = {
	__index:Module.Engine = meta
}

--- Builds the full shell command for executing the engine
--- @param inputline: string - The input file to process
--- @param options: Module.Option - The user-provided options
function meta:build_command(inputline: string, options: Module.Option): string
	-- Step 1: Determine the executable
	local executable = options.engine_executable or self.executable

	-- Step 2: Parse basic options
	local basic_args = self:_parse_basic_options(options)

	-- Step 3: Parse advanced options
	local advanced_args = self:_parse_advanced_options(options)

	-- Step 4: Add engine-specific options
	local engine_specific_args = self:_handle_engine_specific_options(options)

	-- Step 5: Escape and add the input filename
	local input_arg = shellutil.escape(inputline)

	-- Combine all arguments into a single command
	local command = {executable}
	for _, arg_list in ipairs({basic_args, advanced_args, engine_specific_args}) do
		for _, arg in ipairs(arg_list) do
			table.insert(command, arg)
		end
	end

	-- Add the escaped input filename at the end of the command
	table.insert(command, input_arg)

	-- Return the final command string
	return table.concat(command, " ")
end

--- Parses basic options applicable to all engines
function meta:_parse_basic_options(options: Module.Option): {string}
	-- Default option for most engines
	local args = {"-recorder"}

	if options.fmt then
		table.insert(args, "-fmt=" .. options.fmt)
	end

	if options.halt_on_error then
		table.insert(args, "-halt-on-error")
	end

	if options.interaction then
		table.insert(args, "-interaction=" .. options.interaction)
	end

	if options.file_line_error then
		table.insert(args, "-file-line-error")
	end

	if options.synctex then
		table.insert(args, "-synctex=" .. shellutil.escape(options.synctex))
	end

	return args
end

--- Parses advanced options like shell escape and output settings
function meta:_parse_advanced_options(options: Module.Option): {string}
	local args = {}

	-- Handle shell escape settings
	if options.shell_escape == false then
		table.insert(args, "-no-shell-escape")
	elseif options.shell_restricted == true then
		table.insert(args, "-shell-restricted")
	elseif options.shell_escape == true then
		table.insert(args, "-shell-escape")
	end

	if options.jobname then
		table.insert(args, "-jobname=" .. shellutil.escape(options.jobname))
	end

	if options.output_directory then
		table.insert(args, "-output-directory=" .. shellutil.escape(options.output_directory))
	end

	return args
end

--- Handles engine-specific options by calling the relevant handler
function meta:_handle_engine_specific_options(options: Module.Option): {string}
	local args = {}

	-- Call the engine-specific handler if defined
	if self.handle_additional_options then
		self:handle_additional_options(args, options)
	end

	-- Append any extra user-defined options
	if options.extraoptions then
		for _, extra_option in ipairs(options.extraoptions) do
			table.insert(args, extra_option)
		end
	end

	return args
end

--- Constructor for creating a new engine
--- @param name: string - The name of the engine
--- @param supports_pdf_generation: boolean - Whether the engine can generate PDFs
--- @param handle_additional_options?: function - Optional handler for engine-specific options
local function engine(name:string, supports_pdf_generation:boolean, handle_additional_options?:function(self:Module.Engine, args:{string}, options:Module.Option)): Module.Engine
	return setmetatable({
		name = name,
		executable = name,
		supports_pdf_generation = supports_pdf_generation,
		handle_additional_options = handle_additional_options,
		supports_draftmode = supports_pdf_generation,
	}, engine_meta)
end

-- Handles options specific to PDFTeX engines
local function handle_pdftex_options(self:Module.Engine, args:{string}, options:Module.Option)
	if options.draftmode then
		table.insert(args, "-draftmode")
	elseif options.output_format == "dvi" then
		table.insert(args, "-output-format=dvi")
	end
end

-- Handles options specific to XeTeX engines
local function handle_xetex_options(self:Module.Engine, args:{string}, options:Module.Option)
	if options.output_format == "dvi" or options.draftmode then
		table.insert(args, "-no-pdf")
	end
end

-- Handles options specific to LuaTeX engines
local function handle_luatex_options(self:Module.Engine, args:{string}, options:Module.Option)
	if options.lua_initialization_script then
		table.insert(args, "--lua="..shellutil.escape(options.lua_initialization_script))
	end
	handle_pdftex_options(self, args, options)
end

-- Marks an engine as a LuaTeX variant
local function is_luatex(e:Module.Engine): Module.Engine
	e.is_luatex = true
	return e
end

function meta.setup_luatex_initialization(engine:Module.Engine, tex_options:Module.Option, initscriptfile: string): string
	if not engine.is_luatex then
		return
	end
	luatexinit.create_initialization_script(initscriptfile, tex_options)
	return initscriptfile
end

-- TODO can we make handle_additional_options more generic? (think of how some people do key-value passing in golang for example)

-- Define all supported engines with their specific handlers
local KnownEngines:{string:Module.Engine} = {
	["pdftex"]    = engine("pdftex", true, handle_pdftex_options),
	["pdflatex"]  = engine("pdflatex", true, handle_pdftex_options),
	["luatex"]    = is_luatex(engine("luatex", true, handle_luatex_options)),
	["lualatex"]  = is_luatex(engine("lualatex", true, handle_luatex_options)),
	["luajittex"] = is_luatex(engine("luajittex", true, handle_luatex_options)),
	["xetex"]     = engine("xetex", true, handle_xetex_options),
	["xelatex"]   = engine("xelatex", true, handle_xetex_options),
	["tex"]       = engine("tex", false),
	["etex"]      = engine("etex", false),
	["latex"]     = engine("latex", false),
	["ptex"]      = engine("ptex", false),
	["eptex"]     = engine("eptex", false),
	["platex"]    = engine("platex", false),
	["uptex"]     = engine("uptex", false),
	["euptex"]    = engine("euptex", false),
	["uplatex"]   = engine("uplatex", false),
}

KnownEngines["xetex"].dvi_extension = "xdv"
KnownEngines["xelatex"].dvi_extension = "xdv"

local _M:Module = {
	KnownEngines = KnownEngines
}
return _M
