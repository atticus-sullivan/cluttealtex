-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local record Module
	KnownEngines:{string:Engine}

	record Engine
		-- The name of the engine (e.g., "pdftex", "xetex")
		name: string
		-- The executable name to invoke this engine
		executable: string
		-- Whether the engine supports direct PDF generation
		supports_pdf_generation: boolean
		-- Whether the engine supports draft mode
		supports_draftmode: boolean
		-- Indicates if this engine is a LuaTeX variant
		is_luatex: boolean
		-- File extension for DVI output (specific to some engines)
		dvi_extension: string

		-- Function to build the command to execute the engine
		build_command: function(Engine, string, Module.Option): string

		-- Internal helper functions to parse options
		_parse_basic_options: function(Engine, options: Module.Option): {string}
		_parse_advanced_options: function(Engine, options: Module.Option): {string}
		_handle_engine_specific_options: function(Engine, options: Module.Option): {string}

		-- Engine-specific function to handle additional options
		handle_additional_options:function(self:Engine, args:{string}, options:Module.Option)

		setup_luatex_initialization: function(self:Engine, Module.Option, string): string
	end
	record Option
		-- Basic and advanced options for configuring the engine invocation
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

return Module
