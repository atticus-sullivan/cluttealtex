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

local shellutil = require "texrunner.shellutil"

local record Module
	KnownEngines:{string:Engine}

	record Engine
		name: string
		executable: string
		supports_pdf_generation: boolean
		supports_draftmode: boolean
		is_luatex: boolean
		dvi_extension: string

		build_command: function(Engine, string, Module.Option): string
		handle_additional_options:function(self:Engine, args:{string}, options:Module.Option)
	end
	record Option
		halt_on_error: boolean
		interaction: string
		file_line_error: boolean
		synctex: string
		shell_escape: boolean
		shell_restricted: boolean
		jobname: string
		output_directory: string
		extraoptions: {string}
		output_format: string
		draftmode: boolean
		fmt: string
		lua_initialization_script: string
		engine_executable: string
		tex_injection: string
	end
end


--[[
engine.name: string
engine.type = "onePass" or "twoPass"
engine:build_command(inputline, options)
  options:
	halt_on_error: boolean
	interaction: string
	file_line_error: boolean
	synctex: string
	shell_escape: boolean
	shell_restricted: boolean
	jobname: string
	output_directory: string
	extraoptions: a list of strings
	output_format: "pdf" or "dvi"
	draftmode: boolean (pdfTeX / XeTeX / LuaTeX)
	fmt: string
	lua_initialization_script: string (LuaTeX only)
engine.executable: string
engine.supports_pdf_generation: boolean
engine.dvi_extension: string
engine.supports_draftmode: boolean
engine.is_luatex: true or nil
]]

-- local record Engine_meta
-- 	dvi_extension: string
-- 	__index: Engine_meta
-- 	executable: string
--
-- 	handle_additional_options: function(Engine_meta, {string}, Option)
-- 	build_command: function(Engine_meta, string, Option): string
-- end

local meta: Module.Engine = {dvi_extension = "dvi"}
local engine_meta:metatable<Module.Engine> = {
	__index:Module.Engine = meta
}

function meta:build_command(inputline:string, options:Module.Option): string
	local executable = options.engine_executable or self.executable
	local command = {executable, "-recorder"}
	if options.fmt then
		table.insert(command, "-fmt=" .. options.fmt)
	end
	if options.halt_on_error then
		table.insert(command, "-halt-on-error")
	end
	if options.interaction then
		table.insert(command, "-interaction=" .. options.interaction)
	end
	if options.file_line_error then
		table.insert(command, "-file-line-error")
	end
	if options.synctex then
		table.insert(command, "-synctex=" .. shellutil.escape(options.synctex))
	end
	if options.shell_escape == false then
		table.insert(command, "-no-shell-escape")
	elseif options.shell_restricted == true then
		table.insert(command, "-shell-restricted")
	elseif options.shell_escape == true then
		table.insert(command, "-shell-escape")
	end
	if options.jobname then
		table.insert(command, "-jobname=" .. shellutil.escape(options.jobname))
	end
	if options.output_directory then
		table.insert(command, "-output-directory=" .. shellutil.escape(options.output_directory))
	end
	if self.handle_additional_options then
		self:handle_additional_options(command, options)
	end
	if options.extraoptions then
		for _,v in ipairs(options.extraoptions) do
			table.insert(command, v)
		end
	end
	table.insert(command, shellutil.escape(inputline))
	return table.concat(command, " ")
end

-- constructor
local function engine(name:string, supports_pdf_generation:boolean, handle_additional_options:function(self:Module.Engine, args:{string}, options:Module.Option)): Module.Engine
	return setmetatable({
		name = name,
		executable = name,
		supports_pdf_generation = supports_pdf_generation,
		handle_additional_options = handle_additional_options,
		supports_draftmode = supports_pdf_generation,
	}, engine_meta)
end

local function handle_pdftex_options(self:Module.Engine, args:{string}, options:Module.Option)
	if options.draftmode then
		table.insert(args, "-draftmode")
	elseif options.output_format == "dvi" then
		table.insert(args, "-output-format=dvi")
	end
end

local function handle_xetex_options(self:Module.Engine, args:{string}, options:Module.Option)
	if options.output_format == "dvi" or options.draftmode then
		table.insert(args, "-no-pdf")
	end
end

local function handle_luatex_options(self:Module.Engine, args:{string}, options:Module.Option)
	if options.lua_initialization_script then
		table.insert(args, "--lua="..shellutil.escape(options.lua_initialization_script))
	end
	handle_pdftex_options(self, args, options)
end

local function is_luatex(e:Module.Engine): Module.Engine
	e.is_luatex = true
	return e
end

local KnownEngines:{string:Module.Engine} = {
	["pdftex"]   = engine("pdftex", true, handle_pdftex_options),
	["pdflatex"] = engine("pdflatex", true, handle_pdftex_options),
	["luatex"]   = is_luatex(engine("luatex", true, handle_luatex_options)),
	["lualatex"] = is_luatex(engine("lualatex", true, handle_luatex_options)),
	["luajittex"] = is_luatex(engine("luajittex", true, handle_luatex_options)),
	["xetex"]    = engine("xetex", true, handle_xetex_options),
	["xelatex"]  = engine("xelatex", true, handle_xetex_options),
	["tex"]      = engine("tex", false),
	["etex"]     = engine("etex", false),
	["latex"]    = engine("latex", false),
	["ptex"]     = engine("ptex", false),
	["eptex"]    = engine("eptex", false),
	["platex"]   = engine("platex", false),
	["uptex"]    = engine("uptex", false),
	["euptex"]   = engine("euptex", false),
	["uplatex"]  = engine("uplatex", false),
}

KnownEngines["xetex"].dvi_extension = "xdv"
KnownEngines["xelatex"].dvi_extension = "xdv"

local _M:Module = {
	KnownEngines = KnownEngines
}
return _M
