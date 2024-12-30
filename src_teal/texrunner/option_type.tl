local common_t = require"texrunner.common_types"

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
		tex_injection: {number: {(function(options:Options, tex_injection: string): string), string}}

		-- hooks which are run before/after every *TeX invocation
		pre_compile: {number: function}
		post_compile: {number: function}

		-- hooks which are run before/after every the whole build procedure
		-- (potentially includes multiple invocations to *TeX and other tools
		-- like makeindex or biber)
		pre_build: {number: function}
		post_build: {number: function}
	end

	-- stores the allocated priorities
	hook_prios: HookPrios
	record HookPrios
		tex_injection: {string: integer}
	end
	init_hooks: function(): Hooks
end

local _M: Module = {
	hook_prios = {
		tex_injection = {
			includeonly     = 1,
			package_support = 2,
			memoize         = 3,
			quiet           = 4,
		}
	},
	init_hooks = function():Module.Hooks return {
		tex_injection = {},
		pre_compile   = {},
		post_compile  = {},
		pre_build     = {},
		post_build    = {},
	} end
}
return _M
