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

local pathutil     = require "texrunner.pathutil"
local shellutil    = require "texrunner.shellutil"
local parseoption  = require "texrunner.option".parseoption
local TexEngine = require "texrunner.tex_engine"
local message      = require "texrunner.message"
local options = require"texrunner.option_type"

local record Module
	usage: function({string})
	handle_cluttealtex_options: function({string}): string,TexEngine.Engine,options.Options
end

local KnownEngines = TexEngine.KnownEngines
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
		ret.cmd = function(x:string):string return ret.path.." "..s[6] end
	else
		local foo = "%s.%s"
		if ret.type == "makeindex" then
			ret.cmd = function(i:string):string
				i = pathutil.basename(i)
				return ret.path.." "..("-s %s -t %s -o %s %s"):format(
					shellutil.escape(pathutil.replaceext(i,"ist")),
					shellutil.escape(pathutil.replaceext(i,ret.log)),
					shellutil.escape(pathutil.replaceext(i,ret.out)),
					shellutil.escape(pathutil.replaceext(i,ret.inp))
				)
			end
		elseif ret.type == "xindy" then
			ret.cmd = function(i:string):string
				i = pathutil.basename(i)
				return ret.path.." "..("-M %s -t %s -o %s %s"):format(
					shellutil.escape(pathutil.replaceext(i,"ist")),
					shellutil.escape(pathutil.replaceext(i,ret.log)),
					shellutil.escape(pathutil.replaceext(i,ret.out)),
					shellutil.escape(pathutil.replaceext(i,ret.inp))
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
      --start-with-draft       Start with draft mode.
      --[no-]change-directory  Change directory before running TeX.
      --watch[=ENGINE]         Watch input files for change.  Requires fswatch
                                 or inotifywait to be installed. ENGINE is one of
                                 `fswatch', `inotifywait' or `auto' [default: `auto']
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
                                    with a tex-file named "main.tex".
                                    A typical example is
                                    "makeindex:main.acr:main.acn:main.alg" or
                                    "makeindex:main.glo:main.gls:main.glg" (default)
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

local option_spec = {
	-- Options for CluttealTeX
	{
		short = "e",
		long = "engine",
		param = true,
	},
	{
		long = "engine-executable",
		param = true,
	},
	{
		short = "o",
		long = "output",
		param = true,
	},
	{
		long = "fresh",
	},
	{
		long = "max-iterations",
		param = true,
	},
	{
		long = "start-with-draft",
	},
	{
		long = "change-directory",
		boolean = true,
	},
	{
		long = "watch",
		param = true,
		default = "auto",
	},
	{
		short = "h",
		long = "help",
		allow_single_hyphen = true,
	},
	{
		short = "v",
		long = "version",
	},
	{
		short = "V",
		long = "verbose",
	},
	{
		long = "color",
		param = true,
		default = "always",
	},
	{
		long = "includeonly",
		param = true,
	},
	{
		long = "make-depends",
		param = true
	},
	{
		long = "print-output-directory",
	},
	{
		long = "package-support",
		param = true
	},
	{
		long = "check-driver",
		param = true
	},
	-- Options for TeX
	{
		long = "synctex",
		param = true,
		allow_single_hyphen = true,
	},
	{
		long = "file-line-error",
		boolean = true,
		allow_single_hyphen = true,
	},
	{
		long = "interaction",
		param = true,
		allow_single_hyphen = true,
	},
	{
		long = "halt-on-error",
		boolean = true,
		allow_single_hyphen = true,
	},
	{
		long = "shell-escape",
		boolean = true,
		allow_single_hyphen = true,
	},
	{
		long = "shell-restricted",
		allow_single_hyphen = true,
	},
	{
		long = "jobname",
		param = true,
		allow_single_hyphen = true,
	},
	{
		long = "fmt",
		param = true,
		allow_single_hyphen = true,
	},
	{
		long = "output-directory",
		param = true,
		allow_single_hyphen = true,
	},
	{
		long = "output-format",
		param = true,
		allow_single_hyphen = true,
	},
	{
		long = "tex-option",
		param = true,
	},
	{
		long = "tex-options",
		param = true,
	},
	{
		long = "dvipdfmx-option",
		param = true,
	},
	{
		long = "dvipdfmx-options",
		param = true,
	},
	{
		long = "makeindex",
		param = true,
		default = "makeindex",
	},
	{
		long = "bibtex",
		param = true,
		default = "bibtex",
	},
	{
		long = "biber",
		param = true,
		default = "biber",
	},
	{
		long = "sagetex",
		param = true,
		default = "sage",
	},
	{
		long = "glossaries",
		param = true,
		default = "makeindex:main.glo:main.gls:main.glg",
	},
	{
		long = "memoize",
		param = true,
		default = "perl",
	},
	{
		long = "memoize_opt",
		param = true,
	},
}

-- Default values for options
local function set_default_values(options:options.Options)
	if options.max_iterations == nil then
		options.max_iterations = 3
	end

	if options.interaction == nil then
		options.interaction = "nonstopmode"
	end

	if options.file_line_error == nil then
		options.file_line_error = true
	end

	if options.halt_on_error == nil then
		options.halt_on_error = true
	end

	if options.output_format == nil then
		options.output_format = "pdf"
	end
end

-- inputfile, engine, options = handle_cluttealtex_options(arg)
local function handle_cluttealtex_options(arg:{string}): string,TexEngine.Engine,options.Options
	-- Parse options
	local option_and_params, non_option_index = parseoption(arg, option_spec)

	-- Handle options
	local options:options.Options = {
		tex_extraoptions = {},
		dvipdfmx_extraoptions = {},
		package_support = {},
	}
	CLUTTEALTEX_VERBOSITY = 0
	for _,option in ipairs(option_and_params) do
		local name:string = option[1]
		local param:string|boolean = option[2]

		if name == "engine" then
			assert(options.engine == nil, "multiple --engine options")
			if param is string then
				options.engine = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "engine-executable" then
			assert(options.engine_executable == nil, "multiple --engine-executable options")
			if param is string then
				options.engine_executable = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "output" then
			assert(options.output == nil, "multiple --output options")
			if param is string then
				options.output = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "fresh" then
			assert(options.fresh == nil, "multiple --fresh options")
			if param is string then
				options.fresh = true
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "max-iterations" then
			assert(options.max_iterations == nil, "multiple --max-iterations options")
			options.max_iterations = assert(tonumber(param), "invalid value for --max-iterations option")
			assert(options.max_iterations >= 1, "invalid value for --max-iterations option")

		elseif name == "start-with-draft" then
			assert(options.start_with_draft == nil, "multiple --start-with-draft options")
			options.start_with_draft = true

		elseif name == "watch" then
			assert(options.watch == nil, "multiple --watch options")
			if param is string then
				options.watch = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "help" then
			usage(arg)
			os.exit(0)

		elseif name == "version" then
			io.stderr:write("cluttealtex ",CLUTTEALTEX_VERSION,"\n")
			os.exit(0)

		elseif name == "verbose" then
			CLUTTEALTEX_VERBOSITY = CLUTTEALTEX_VERBOSITY + 1

		elseif name == "color" then
			assert(options.color == nil, "multiple --color options")
			if param is string then
				options.color = param
			else
				assert(param is string, "invalid param type")
			end
			message.set_colors(options.color)

		elseif name == "change-directory" then
			assert(options.change_directory == nil, "multiple --change-directory options")
			if param is boolean then
				options.change_directory = param
			else
				assert(param is boolean, "invalid param type")
			end

		elseif name == "includeonly" then
			assert(options.includeonly == nil, "multiple --includeonly options")
			if param is string then
				options.includeonly = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "make-depends" then
			assert(options.make_depends == nil, "multiple --make-depends options")
			if param is string then
				options.make_depends = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "print-output-directory" then
			assert(options.print_output_directory == nil, "multiple --print-output-directory options")
			if param is string then
				options.print_output_directory = true
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "package-support" then
			local known_packages:{string:boolean} = {["minted"] = true, ["epstopdf"] = true}
			if param is string then
				for pkg in string.gmatch(param, "[^,%s]+") do
					options.package_support[pkg] = true
					if not known_packages[pkg] and CLUTTEALTEX_VERBOSITY >= 1 then
						message.warn("CluttealTeX provides no special support for '"..pkg.."'.")
					end
				end
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "check-driver" then
			assert(options.check_driver == nil, "multiple --check-driver options")
			assert(param == "dvipdfmx" or param == "dvips" or param == "dvisvgm", "wrong value for --check-driver option")
			if param is string then
				options.check_driver = param
			else
				assert(param is string, "invalid param type")
			end

			-- Options for TeX
		elseif name == "synctex" then
			assert(options.synctex == nil, "multiple --synctex options")
			if param is string then
				options.synctex = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "file-line-error" then
			if param is boolean then
				options.file_line_error = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "interaction" then
			assert(options.interaction == nil, "multiple --interaction options")
			if param is string then
				assert(param == "batchmode" or param == "nonstopmode" or param == "scrollmode" or param == "errorstopmode", "invalid argument for --interaction")
				options.interaction = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "halt-on-error" then
			if param is boolean then
				options.halt_on_error = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "shell-escape" then
			assert(options.shell_escape == nil and options.shell_restricted == nil, "multiple --(no-)shell-escape or --shell-restricted options")
			if param is boolean then
				options.shell_escape = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "shell-restricted" then
			assert(options.shell_escape == nil and options.shell_restricted == nil, "multiple --(no-)shell-escape or --shell-restricted options")
			options.shell_restricted = true

		elseif name == "jobname" then
			assert(options.jobname == nil, "multiple --jobname options")
			if param is string then
				options.jobname = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "fmt" then
			assert(options.fmt == nil, "multiple --fmt options")
			if param is string then
				options.fmt = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "output-directory" then
			assert(options.output_directory == nil, "multiple --output-directory options")
			if param is string then
				options.output_directory = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "output-format" then
			assert(options.output_format == nil, "multiple --output-format options")
			assert(param == "pdf" or param == "dvi", "invalid argument for --output-format")
			if param is string then
				options.output_format = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "tex-option" then
			if param is string then
				table.insert(options.tex_extraoptions, shellutil.escape(param))
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "tex-options" then
			if param is string then
				table.insert(options.tex_extraoptions, param)
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "dvipdfmx-option" then
			if param is string then
				table.insert(options.dvipdfmx_extraoptions, shellutil.escape(param))
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "dvipdfmx-options" then
			if param is string then
				table.insert(options.dvipdfmx_extraoptions, param)
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "makeindex" then
			assert(not options.glossaries, "'makeindex' cannot be used together with 'glossaries'\nUse e.g. --glossaries='makeindex:main.ind:main.idx:main.ilg' instead of makeindex")
			assert(options.makeindex == nil, "multiple --makeindex options")
			if param is string then
				options.makeindex = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "bibtex" then
			assert(options.bibtex == nil, "multiple --bibtex options")
			assert(options.biber == nil, "multiple --bibtex/--biber options")
			if param is string then
				options.bibtex = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "biber" then
			assert(options.biber == nil, "multiple --biber options")
			assert(options.bibtex == nil, "multiple --bibtex/--biber options")
			if param is string then
				options.biber = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "glossaries" then
			assert(not options.makeindex, "'glossaries' cannot be used together with 'makeindex'\nUse e.g. --glossaries='makeindex:main.ind:main.idx:main.ilg' instead of makeindex")
			if not options.glossaries then
				options.glossaries = {}
			end
			if param is string then
				local cfg = assert(parse_glossaries_option(param))
				table.insert(options.glossaries, cfg)
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "sagetex" then
			assert(options.sagetex == nil, "multiple --sagetex options")
			if param is string then
				options.sagetex = param
			else
				assert(param is string, "invalid param type")
			end

		elseif name == "memoize" then
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
				assert(param is string, "invalid param type")
			end

		elseif name == "memoize_opt" then
			if param is string then
				options.memoize_opts = options.memoize_opts or {}
				table.insert(options.memoize_opts, param)
			else
				assert(param is string, "invalid param type")
			end

		end

	end

	if options.color == nil then
		message.set_colors("auto")
	end

	-- Handle non-options (i.e. input file)
	if non_option_index > #arg then
		-- No input file given
		usage(arg)
		os.exit(1)
	elseif non_option_index < #arg then
		message.error("Multiple input files are not supported.")
		os.exit(1)
	end
	local inputfile = arg[non_option_index]

	-- If run as 'cllualatex', then the default engine is lualatex
	if options.engine == nil and type(arg[0]) == "string" then
		local basename = pathutil.trimext(pathutil.basename(arg[0]))
		local engine_part = string.match(basename, "^cl(%w+)$")
		if engine_part and KnownEngines[engine_part] then
			options.engine = engine_part
		end
	end

	if options.engine == nil then
		message.error("Engine not specified.")
		os.exit(1)
	end
	local engine = KnownEngines[options.engine]
	if not engine then
		message.error("Unknown engine name '", options.engine, "'.")
		os.exit(1)
	end

	set_default_values(options)

	-- parameter validy check TODO should this be organized as function like
	-- set_default_values and with a key in the option spec (list or function)?
	if options.watch then
		if options.watch ~= "fswatch" and options.watch ~= "inotifywait" then
			message.error("Unknown wait engine '", options.watch, "'.")
			os.exit(1)
		end
	end

	if options.output_format == "pdf" then
		if options.check_driver ~= nil then
			error("--check-driver can only be used when the output format is DVI.")
		end
		if engine.supports_pdf_generation then
			if engine.is_luatex then
				options.check_driver = "luatex"
			elseif engine.name == "xetex" or engine.name == "xelatex" then
				options.check_driver = "xetex"
			elseif engine.name == "pdftex" or engine.name == "pdflatex" then
				options.check_driver = "pdftex"
			else
				message.warn("Unknown engine: "..engine.name)
				message.warn("Driver check will not work.")
			end
		else
			-- CluttealTeX uses dvipdfmx to generate PDF from DVI output.
			options.check_driver = "dvipdfmx"
		end
	end

	return inputfile, engine, options
end

local _M:Module = {
	usage = usage,
	handle_cluttealtex_options = handle_cluttealtex_options,
}
return _M
