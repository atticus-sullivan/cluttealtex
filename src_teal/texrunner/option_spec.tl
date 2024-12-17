local COPYRIGHT_NOTICE = [[
Copyright (C) 2016-2021  ARATA Mizuki
Copyright (C) 2024 Lukas Heindl

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

local Option  = require "texrunner.option".Option
local shellutil   = require "texrunner.shellutil"
local options = require"texrunner.option_type"
local pathutil    = require "texrunner.pathutil"
local message     = require "texrunner.message"

global CLUTTEALTEX_VERSION:string

local function split(opt:string): {string}
	local ret,builder,state = {},{},0
	for c in opt:gmatch(".") do
		if state == 0 then
			if c == ":" then
				table.insert(ret, table.concat(builder, ""))
				builder = {}
			elseif c == "\\" then
				state = 1
			else
				table.insert(builder, c)
			end

		elseif state == 1 then
			-- escaped
			table.insert(builder, c)
			state = 0
		end
	end
	table.insert(ret, table.concat(builder, ""))
	return ret
end

local function parse_glossaries_option(opt:string): options.Glos, string
	local s = split(opt)
	if #s < 2 or #s > 6 then
		return nil, "Error on splitting the glossaries parameter \""..opt.."\""
	end

	local ret:options.Glos = {}

	ret.type = s[1]
	if ret.type ~= "makeindex" and ret.type ~= "xindy" and (#s ~= 7 or s[5] == "") then
		return nil, "Invalid glossaries parameter. \""..ret.type.."\" is unsupported"
	end

	ret.out = s[2]

	if #s >= 3 and s[3] ~= "" then
		ret.inp = s[3]
	else
		ret.inp = ret.out:sub(1,-2).."o"
	end

	if #s >= 4 and s[4] ~= "" then
		ret.log = s[4]
	else
		ret.log = ret.out:sub(1,-2).."g"
	end

	if #s >= 5 and s[5] ~= "" then
		ret.path = s[5]
	else
		ret.path = ret.type
	end

	if #s >= 6 then
		ret.cmd = function(path_in_output_directory: function(ext:string):string):string return ret.path.." "..s[6] end
	else
		local foo = "%s.%s"
		if ret.type == "makeindex" then
			ret.cmd = function(path_in_output_directory: function(ext:string):string):string
				return ret.path.." "..("-s %s -t %s -o %s %s"):format(
					shellutil.escape(path_in_output_directory("ist")),
					shellutil.escape(path_in_output_directory(ret.log)),
					shellutil.escape(path_in_output_directory(ret.out)),
					shellutil.escape(path_in_output_directory(ret.inp))
				)
			end
		elseif ret.type == "xindy" then
			ret.cmd = function(path_in_output_directory: function(ext:string):string):string
				return ret.path.." "..("-M %s -t %s -o %s %s"):format(
					shellutil.escape(path_in_output_directory("ist")),
					shellutil.escape(path_in_output_directory(ret.log)),
					shellutil.escape(path_in_output_directory(ret.out)),
					shellutil.escape(path_in_output_directory(ret.inp))
				)
			end
		else
			return nil, "Error on parsing the glossaries parameter \""..opt.."\""
		end
	end

	return ret
end

local function usage(arg:{string})
	io.write(string.format([[
ClutteakTeX: Process TeX files without cluttering your working directory

Usage:
  %s [options] [--] FILE.tex

Options:
  -e, --engine=ENGINE          Specify which TeX engine to use.
                                 ENGINE is one of the following:
                                     pdflatex, pdftex,
                                     lualatex, luatex, luajittex,
                                     xelatex, xetex, latex, etex, tex,
                                     platex, eptex, ptex,
                                     uplatex, euptex, uptex,
      --engine-executable=COMMAND+OPTIONs
                               The actual TeX command to use.
                                 [default: ENGINE]
  -o, --output=FILE            The name of output file.
                                 [default: JOBNAME.pdf or JOBNAME.dvi]
      --fresh                  Clean intermediate files before running TeX.
                                 Cannot be used with --output-directory.
      --max-iterations=N       Maximum number of running TeX to resolve
                                 cross-references.  [default: 3]
      --skip-first             Skip first run if possible [default: false]
      --start-with-draft       Start with draft mode.
      --[no-]change-directory  Change directory before running TeX.
      --watch[=ENGINE]         Watch input files for change.  Requires fswatch
                                 or inotifywait to be installed. ENGINE is one of
                                 `fswatch', `inotifywait' or `auto' [default: `auto']
      --watch-only-path=PATH   Only watch input files that reside beneath the specified path
                                 precedence follows the order of specified arguments
                                 using this option automatically makes NOT watching files the default
      --watch-not-path=PATH    Don't watch input files that reside beneath the specified path
                                 precedence follows the order of specified arguments
                                 using this option automatically makes NOT watching files the default
                                 (consider using --watch-only-path=/ first if you don't want this)
      --watch-only-ext=EXT     Only watch input files with the specified extension
                                 precedence follows the order of specified arguments
                                 using this option automatically makes NOT watching files the default
      --watch-not-ext=EXT      Don't watch input files with the specified extension
                                 precedence follows the order of specified arguments
                                 using this option automatically makes NOT watching files the default
                                 (consider using --watch-only-path=/ first if you don't want this)
      --tex-option=OPTION      Pass OPTION to TeX as a single option.
      --tex-options=OPTIONs    Pass OPTIONs to TeX as multiple options.
      --dvipdfmx-option[s]=OPTION[s]  Same for dvipdfmx.
      --makeindex=COMMAND+OPTIONs   Command to generate index, such as
                                     `makeindex' or `mendex'.
      --bibtex=COMMAND+OPTIONs      Command for BibTeX, such as
                                     `bibtex' or `pbibtex'.
      --biber[=COMMAND+OPTIONs]     Command for Biber.
      --sagetex[=COMMAND+OPTIONS]   Command for sagetex
      --memoize[=python/perl/path]  Command which shall be used for memoize
      --memoize_opt=PACKAGE_OPT     Additional package option for memoize
      --glossaries=[CONFIGURATION]  Configuration can contain
                                    "type:outputFile:inputFile:logFile:pathToCommand:commandArgs" (":" can be escaped with "\").
                                    Only the outputFile and either type or pathToCommand
                                    are required, the other options will be infered
                                    automatically (does not work always for inputFile and
                                    logFile). If commandArgs is being specified,
                                    these will be the only arguments passed to the
                                    command. If type is unspecified commandArgs must be
                                    specified. As types we support makeindex and xindy.
                                    Specify this option multiple times to register multiple
                                    glossaries. The default value works for a
                                    configuration with the usual glossary (glo,gls,glg)
                                    A typical example is
                                    "makeindex:acr:acn:alg" or
                                    "makeindex:glo:gls:glg" (default)
  -h, --help                   Print this message and exit.
  -v, --version                Print version information and exit.
  -V, --verbose                Be more verbose.
      --color[=WHEN]           Make CluttealTeX's message colorful. WHEN is one of
                                 `always', `auto', or `never'.
                                 [default: `auto' if --color is omitted,
                                           `always' if WHEN is omitted]
      --includeonly=NAMEs      Insert '\includeonly{NAMEs}'.
      --make-depends=FILE      Write dependencies as a Makefile rule.
      --print-output-directory  Print the output directory and exit.
      --package-support=PKG1[,PKG2,...]
                               Enable special support for some shell-escaping
                                 packages.
                               Currently supported: minted, epstopdf
      --check-driver=DRIVER    Check that the correct driver file is loaded.
                               DRIVER is one of `dvipdfmx', `dvips', `dvisvgm'.

      --[no-]shell-escape
      --shell-restricted
      --synctex=NUMBER
      --fmt=FMTNAME
      --[no-]file-line-error   [default: yes]
      --[no-]halt-on-error     [default: yes]
      --interaction=STRING     [default: nonstopmode]
      --jobname=STRING
      --output-directory=DIR   [default: somewhere in the temporary directory]
      --output-format=FORMAT   FORMAT is `pdf' or `dvi'.  [default: pdf]

%s
]], arg[0] or 'texlua cluttealtex.lua', COPYRIGHT_NOTICE))
end


local option_spec:{string:Option} = {
	-- Options for CluttealTeX
	engine = {
		short = "e",
		long = "engine",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.engine == nil, "multiple --engine options")
			if param is string then
				options.engine = param
			else
				error("invalid param type")
			end
		end
	},
	engine_executable = {
		long = "engine-executable",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.engine_executable == nil, "multiple --engine-executable options")
			if param is string then
				options.engine_executable = param
			else
				error("invalid param type")
			end
		end
	},
	output = {
		short = "o",
		long = "output",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.output == nil, "multiple --output options")
			if param is string then
				options.output = param
			else
				error("invalid param type")
			end
		end
	},
	fresh = {
		long = "fresh",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.fresh == nil, "multiple --fresh options")
			if param is string then
				options.fresh = true
			else
				error("invalid param type")
			end
		end
	},
	max_iterations = {
		long = "max-iterations",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.max_iterations == nil, "multiple --max-iterations options")
			options.max_iterations = assert(tonumber(param) as integer, "invalid value for --max-iterations option")
			assert(options.max_iterations >= 1, "invalid value for --max-iterations option")
		end
	},
	skip_first = {
		long = "skip-first",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.skip_first == nil, "multiple --skip-first options")
			options.skip_first = true
		end
	},
	start_with_draft = {
		long = "start-with-draft",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.start_with_draft == nil, "multiple --start-with-draft options")
			options.start_with_draft = true
		end
	},
	change_directory = {
		long = "change-directory",
		boolean = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.change_directory == nil, "multiple --change-directory options")
				if param is boolean then
					options.change_directory = param
					else
					error("invalid param type")
				end
			end
	},
	watch = {
		long = "watch",
		param = true,
		default = "auto",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.watch == nil, "multiple --watch options")
			if param is string then
				options.watch = param
			else
				error("invalid param type")
			end
		end
	},
	watch_only_path = {
		long = "watch-only-path",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				if not options.watch_inc_exc then options.watch_inc_exc = {} end
				table.insert(options.watch_inc_exc, {param=pathutil.abspath(param),type='only_path'})
			else
				error("invalid param type")
			end
		end
	},
	watch_not_path = {
		long = "watch-not-path",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				if not options.watch_inc_exc then options.watch_inc_exc = {} end
				table.insert(options.watch_inc_exc, {param=pathutil.abspath(param),type='not_path'})
			else
				error("invalid param type")
			end
		end
	},
	watch_only_ext = {
		long = "watch-only-ext",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				if not options.watch_inc_exc then options.watch_inc_exc = {} end
				table.insert(options.watch_inc_exc, {param=param,type='only_ext'})
			else
				error("invalid param type")
			end
		end
	},
	watch_not_ext = {
		long = "watch-not-ext",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				if not options.watch_inc_exc then options.watch_inc_exc = {} end
				table.insert(options.watch_inc_exc, {param=param,type='not_ext'})
			else
				error("invalid param type")
			end
		end
	},
	help = {
		short = "h",
		long = "help",
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			usage(arg)
			os.exit(0)
		end
	},
	version = {
		short = "v",
		long = "version",
		handle_cli = function(options:options.Options, param:string|boolean)
			io.stderr:write("cluttealtex ",CLUTTEALTEX_VERSION,"\n")
			os.exit(0)
		end
	},
	verbose = {
		short = "V",
		long = "verbose",
		handle_cli = function(options:options.Options, param:string|boolean)
			CLUTTEALTEX_VERBOSITY = CLUTTEALTEX_VERBOSITY + 1
		end
	},
	color = {
		long = "color",
		param = true,
		default = "always",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.color == nil, "multiple --color options")
			if param is string then
				options.color = param
			else
				error("invalid param type")
			end
			message.set_colors(options.color)
		end
	},
	includeonly = {
		long = "includeonly",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.includeonly == nil, "multiple --includeonly options")
			if param is string then
				options.includeonly = param
			else
				error("invalid param type")
			end
		end
	},
	make_depends = {
		long = "make-depends",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.make_depends == nil, "multiple --make-depends options")
			if param is string then
				options.make_depends = param
			else
				error("invalid param type")
			end
		end
	},
	print_output_directory = {
		long = "print-output-directory",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.print_output_directory == nil, "multiple --print-output-directory options")
			if param is string then
				options.print_output_directory = true
			else
				error("invalid param type")
			end
		end
	},
	package_support = {
		long = "package-support",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			local known_packages:{string:boolean} = {["minted"] = true, ["epstopdf"] = true}
			if param is string then
				for pkg in string.gmatch(param, "[^,%s]+") do
					options.package_support[pkg] = true
					if not known_packages[pkg] and CLUTTEALTEX_VERBOSITY >= 1 then
						message.warn("CluttealTeX provides no special support for '"..pkg.."'.")
					end
				end
			else
				error("invalid param type")
			end
		end
	},
	check_driver = {
		long = "check-driver",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.check_driver == nil, "multiple --check-driver options")
			assert(param == "dvipdfmx" or param == "dvips" or param == "dvisvgm", "wrong value for --check-driver option")
			if param is string then
				options.check_driver = param
			else
				assert(param is string, "invalid param type")
			end
		end
	},
	-- Options for TeX
	synctex = {
		long = "synctex",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.synctex == nil, "multiple --synctex options")
			if param is string then
				options.synctex = param
			else
				error("invalid param type")
			end
		end
	},
	file_line_error = {
		long = "file-line-error",
		boolean = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is boolean then
				options.file_line_error = param
			else
				assert(param is string, "invalid param type")
			end
		end
	},
	interaction = {
		long = "interaction",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.interaction == nil, "multiple --interaction options")
			if param is string then
				assert(param == "batchmode" or param == "nonstopmode" or param == "scrollmode" or param == "errorstopmode", "invalid argument for --interaction")
				options.interaction = param
			else
				error("invalid param type")
			end
		end
	},
	halt_on_error = {
		long = "halt-on-error",
		boolean = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is boolean then
				options.halt_on_error = param
			else
				assert(param is string, "invalid param type")
			end
		end
	},
	shell_escape = {
		long = "shell-escape",
		boolean = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.shell_escape == nil and options.shell_restricted == nil, "multiple --(no-)shell-escape or --shell-restricted options")
			if param is boolean then
				options.shell_escape = param
			else
				assert(param is string, "invalid param type")
			end
		end
	},
	shell_restricted = {
		long = "shell-restricted",
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.shell_escape == nil and options.shell_restricted == nil, "multiple --(no-)shell-escape or --shell-restricted options")
			options.shell_restricted = true
		end
	},
	jobname = {
		long = "jobname",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.jobname == nil, "multiple --jobname options")
			if param is string then
				options.jobname = param
			else
				error("invalid param type")
			end
		end
	},
	fmt = {
		long = "fmt",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.fmt == nil, "multiple --fmt options")
			if param is string then
				options.fmt = param
			else
				error("invalid param type")
			end
		end
	},
	output_directory = {
		long = "output-directory",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.output_directory == nil, "multiple --output-directory options")
			if param is string then
				options.output_directory = param
			else
				error("invalid param type")
			end
		end
	},
	output_format = {
		long = "output-format",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.output_format == nil, "multiple --output-format options")
			assert(param == "pdf" or param == "dvi", "invalid argument for --output-format")
			if param is string then
				options.output_format = param
			else
				assert(param is string, "invalid param type")
			end
		end
	},
	tex_option = {
		long = "tex-option",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				table.insert(options.tex_extraoptions, shellutil.escape(param))
			else
				error("invalid param type")
			end
		end
	},
	tex_options = {
		long = "tex-options",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				table.insert(options.tex_extraoptions, param)
			else
				error("invalid param type")
			end
		end
	},
	dvipdfmx_option = {
		long = "dvipdfmx-option",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				table.insert(options.dvipdfmx_extraoptions, shellutil.escape(param))
			else
				error("invalid param type")
			end
		end
	},
	dvipdfmx_options = {
		long = "dvipdfmx-options",
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				table.insert(options.dvipdfmx_extraoptions, param)
			else
				error("invalid param type")
			end
		end
	},
	makeindex = {
		long = "makeindex",
		param = true,
		default = "makeindex",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(not options.glossaries, "'makeindex' cannot be used together with 'glossaries'\nUse e.g. --glossaries='makeindex:main.ind:main.idx:main.ilg' instead of makeindex")
			assert(options.makeindex == nil, "multiple --makeindex options")
			if param is string then
				options.makeindex = param
			else
				error("invalid param type")
			end
		end
	},
	bibtex = {
		long = "bibtex",
		param = true,
		default = "bibtex",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.bibtex == nil, "multiple --bibtex options")
			assert(options.biber == nil, "multiple --bibtex/--biber options")
			if param is string then
				options.bibtex = param
			else
				error("invalid param type")
			end
		end
	},
	biber = {
		long = "biber",
		param = true,
		default = "biber",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.biber == nil, "multiple --biber options")
			assert(options.bibtex == nil, "multiple --bibtex/--biber options")
			if param is string then
				options.biber = param
			else
				error("invalid param type")
			end
		end
	},
	sagetex = {
		long = "sagetex",
		param = true,
		default = "sage",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.sagetex == nil, "multiple --sagetex options")
			if param is string then
				options.sagetex = param
			else
				error("invalid param type")
			end
		end
	},
	glossaries = {
		long = "glossaries",
		param = true,
		default = "makeindex:main.glo:main.gls:main.glg",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(not options.makeindex, "'glossaries' cannot be used together with 'makeindex'\nUse e.g. --glossaries='makeindex:main.ind:main.idx:main.ilg' instead of makeindex")
			if not options.glossaries then
				options.glossaries = {}
			end
			if param is string then
				local cfg = assert(parse_glossaries_option(param))
				table.insert(options.glossaries, cfg)
			else
				error("invalid param type")
			end
		end
	},
	memoize = {
		long = "memoize",
		param = true,
		default = "perl",
		handle_cli = function(options:options.Options, param:string|boolean)
			assert(options.memoize == nil, "multiple --memoize options")
			if param is string then
				if param == "python" then
					options.memoize = "memoize-extract.py"
				elseif param == "perl" then
					options.memoize = "memoize-extract.pl"
				else
					options.memoize = param
				end
			else
				error("invalid param type")
			end
		end
	},
	memoize_opt = {
		long = "memoize_opt", -- TODO should be memoize-opt on commandline probably, but is breaking
		param = true,
		handle_cli = function(options:options.Options, param:string|boolean)
			if param is string then
				options.memoize_opts = options.memoize_opts or {}
				table.insert(options.memoize_opts, param)
			else
				error("invalid param type")
			end
		end
	},
}

return {
	spec = option_spec,
	usage = usage,
}
