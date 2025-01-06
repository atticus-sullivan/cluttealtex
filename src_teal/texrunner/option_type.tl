-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local common_t = require"texrunner.common_types"
local engine_t = require"texrunner.tex_engine"

local record Module
	record Options
		biber: string
		bibtex: string
		change_directory: boolean
		check_driver: string
		color: string
		dvipdfmx_extraoptions: {string}
		engine: string
		engine_executable: string
		file_line_error: boolean
		fresh: boolean
		glossaries: {Glos}
		halt_on_error: boolean
		includeonly: string
		interaction: string
		jobname: string
		make_depends: string
		max_iterations: integer
		output: string -- file in which the output is in the end
		outfile: string -- file to which *TeX is compiling to
		output_directory: string
		output_format: string
		package_support: {string:boolean}
		print_output_directory: boolean
		shell_escape: boolean
		shell_restricted: boolean
		start_with_draft: boolean
		skip_first: boolean
		synctex: string
		tex_extraoptions: {string}
		watch: string
		watch_filter: {WatchFilter}
		fmt: string
		makeindex: string
		sagetex: string
		memoize: string
		memoize_opts: {string}
		extraoptions: {string}
		quiet: integer

		hooks: Hooks
	end
	record WatchFilter
		type: string
		param: string
	end
	record Glos
		-- only used for splitting and cmd building
		type: string
		log: string
		path: string
		-- used during compilation
		out: string
		inp: string
		-- used during compilation
		-- takes the name of the inputfile as an argument and returns the
		-- formatted command
		cmd: function(function(string):string): string
	end

	-- hooks are always associated with a priority and a descriptive string
	-- a low number means a high priority -> is executed first
	record Hooks
		-- hooks used to inject code into the *TeX input
		-- hooks need to return the new tex_injection string (usually they should only prepend/append)
		type tex_injection_func = function(options:Options, engine_t.Option, tex_injection: string): string
		tex_injection: {number: {tex_injection_func, string}}

		-- hooks which are run before/after every *TeX invocation
		-- pre_compile: {number: function}
		type post_compile_func = function(Options, PostCompileArgs)
		post_compile: {number: {post_compile_func, string}}

		-- hooks which are run before/after every the whole build procedure
		-- (potentially includes multiple invocations to *TeX and other tools
		-- like makeindex or biber)
		-- pre_build: {number: function}
		type post_build_func = function(Options)
		post_build: {number: {post_build_func,string}}

		-- hooks which run when a recorder file is being parsed before running
		-- *TeX in order to suggest some options based on the files from the
		-- filelist
		-- the third value in the tuple is used to store if the message (second
		-- value in the tuple) has already been shown to the user
		type suggestion_file_based_func = function(common_t.Filemap_ele):boolean
		suggestion_file_based: {number: {suggestion_file_based_func, string, boolean}}

		-- hooks which check the execlog if some option should be probably used
		type suggestion_execlog_based_func = function(string, Options):boolean
		suggestion_execlog_based: {number: {suggestion_execlog_based_func, string}}
	end

	-- stores the allocated priorities
	hook_prios: HookPrios
	type HookPriosTab = {string:integer}
	record HookPrios
		tex_injection:         HookPriosTab

		suggestion_file_based:    HookPriosTab
		suggestion_execlog_based: HookPriosTab

		-- pre_compile:           HookPriosTab
		post_compile:          HookPriosTab

		-- pre_build:             HookPriosTab
		post_build:            HookPriosTab
	end

	-- argument collections related to special hooks
	record PostCompileArgs
		filelist: common_t.filelist
		auxstatus: common_t.auxstatus
		path_in_output_directory: function(string):string
		bibtex_aux_hash: string
		original_wd: string
	end
end

local _M: Module = {
	hook_prios = {
		tex_injection = {
			includeonly     = 1,
			package_support = 2,
			memoize         = 3,
			quiet           = 4,
		},
		suggestion_file_based = {
			package_support = 2,
		},
		post_compile = {
			checkdriver = 1,
			makeindex   = 2,
			glossaries  = 3,
			bibtex      = 4,
			biber       = 5,
			memoize     = 6,
			sagetex     = 7,
		},
		suggestion_execlog_based = {
			checkdriver = 1,
			makeindex   = 2,
			glossaries  = 3,
			bibtex      = 4,
			biber       = 5,
			memoize     = 6,
			sagetex     = 7,
		},
		post_build = {},
	},
}
return _M
