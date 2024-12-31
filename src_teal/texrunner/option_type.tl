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
		output: string
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
		watch_inc_exc: {WatchIncExc}
		fmt: string
		makeindex: string
		sagetex: string
		memoize: string
		memoize_opts: {string}
		extraoptions: {string}
		quiet: integer

		hooks: Hooks
	end
	record WatchIncExc
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
		tex_injection: {number: {(function(options:Options, engine_t.Option, tex_injection: string): string), string}}

		-- hooks which are run before/after every *TeX invocation
		-- pre_compile: {number: function}
		post_compile: {number: {(function(Options, PostCompileArgs)), string}}

		-- hooks which are run before/after every the whole build procedure
		-- (potentially includes multiple invocations to *TeX and other tools
		-- like makeindex or biber)
		-- pre_build: {number: function}
		-- post_build: {number: function}

		-- hooks which run when a recorder file is being parsed before running
		-- *TeX in order to suggest some options based on the files from the
		-- filelist
		-- the third value in the tuple is used to store if the message (second
		-- value in the tuple) has already been shown to the user
		suggestion_file_based: {number: {(function(common_t.Filemap_ele):boolean), string, boolean}}

		-- hooks which check the execlog if some option should be probably used
		suggestion_execlog_based: {number: {(function(string, Options):boolean), string}}
	end

	-- stores the allocated priorities
	hook_prios: HookPrios
	record HookPrios
		tex_injection:         {string: integer}

		suggestion_file_based:    {string: integer}
		suggestion_execlog_based: {string: integer}

		-- pre_compile:           {string: integer}
		post_compile:          {string: integer}

		-- pre_build:             {string: integer}
		-- post_build:            {string: integer}
	end

	-- argument collections related to special hooks
	record PostCompileArgs
		filelist: {common_t.Filemap_ele}
		auxstatus: {string: common_t.Status}
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
		}
	},
}
return _M
