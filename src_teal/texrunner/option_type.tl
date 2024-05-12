local record Module
	record Options_glos
		out:string
		inp: string
	end
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
		synctex: string
		tex_extraoptions: {string}
		watch: string
		fmt: string
		makeindex: string
		sagetex: string
		memoize: string
		memoize_opts: {string}
		extraoptions: {string}
	end
	record Glos
		type: string -- only used for splitting and cmd building
		out: string -- used during compilation
		inp: string -- used during compilation
		log: string -- only used for splitting and cmd building
		path: string -- only used for splitting and cmd building
		ist: string -- only used for splitting and cmd building
		args: string -- only used for splitting and cmd building
		cmd: string -- used during compilation
	end

end

local _M: Module = {}
return _M
