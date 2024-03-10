local record Module
	record Options_glos
		out:string
		inp: string
	end
	record Options
		biber: string
		bibtex: string
		change_directory: string
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
		makeglossaries: string
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
		extraoptions: {string}
	end
	record Glos
		type: string
		out: string
		inp: string
		log: string
		path: string
		ist: string
		args: string
		cmd: string
	end

end

local _M: Module = {}
return _M
