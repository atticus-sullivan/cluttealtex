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

local Option        = require "texrunner.option".Option
local shellutil     = require "texrunner.shellutil"
local option_t      = require"texrunner.option_type"
local pathutil      = require "texrunner.pathutil"
local message       = require "texrunner.message"
local typeset_hooks = require "texrunner.typeset_hooks"
local common_t      = require "texrunner.common_types"

global CLUTTEALTEX_VERSION:string

local record Module
	spec:{string:Option}
	usage:function({string})
	init_hooks: function(option_t.Options)
	_internal: Internal
	record Internal
		split: function(opt:string): {string}
		parse_glossaries_option_from_table: function(opt:{string:string|nil}): option_t.Glos, string
		parse_glossaries_option_from_string: function(opt:string): option_t.Glos, string
		usage_ele: function(optname:string, opt:Option, alignment:alignRec):outRec
	end
end
local _M:Module = {}

function _M.init_hooks(o:option_t.Options)
	o.hooks = o.hooks or {}

	o.hooks.tex_injection            = {}
	-- o.hooks.pre_compile              = {}
	o.hooks.post_compile             = {}
	-- o.hooks.pre_build                = {}
	o.hooks.post_build               = {}
	o.hooks.suggestion_file_based    = {}
	o.hooks.suggestion_execlog_based = {}

	for _,v in pairs(_M.spec) do
		if v.suggestion_handlers and v.suggestion_handlers.file_based then
			v.suggestion_handlers.file_based(o)
		end
		if v.suggestion_handlers and v.suggestion_handlers.execlog_based then
			v.suggestion_handlers.execlog_based(o)
		end
	end
end

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

local function parse_glossaries_option_from_table(opt:{string:string|nil}): option_t.Glos, string
	local ret:option_t.Glos = {}

	ret.type = opt.type or ""
	if not (ret.type == "makeindex" or ret.type == "xindy" or (opt.path and opt.path ~= "")) then
		return nil, "Invalid glossaries parameter. \""..ret.type.."\" is unsupported"
	end

	if not opt.out then
		return nil, "'out' must be set"
	end
	ret.out = opt.out

	if opt.inp and opt.inp ~= "" then
		ret.inp = opt.inp
	else
		ret.inp = ret.out:sub(1,-2).."o"
	end

	if opt.log and opt.log ~= "" then
		ret.log = opt.log
	else
		ret.log = ret.out:sub(1,-2).."g"
	end

	if opt.path and opt.path ~= "" then
		ret.path = opt.path
	else
		ret.path = ret.type
	end

	if opt.cmd_args then
		ret.cmd = function(path_in_output_directory: function(ext:string):string):string return ret.path.." "..opt.cmd_args end
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
			return nil, "Error on parsing the glossaries parameter"
		end
	end

	return ret
end

local function parse_glossaries_option_from_string(opt:string): option_t.Glos, string
	local s = split(opt)
	if #s < 2 or #s > 6 then
		return nil, "Error on splitting the glossaries parameter \""..opt.."\""
	end
	return parse_glossaries_option_from_table{type=s[1], out=s[2], inp=s[3], log=s[4], path=s[5], cmd_args=s[6]}
end

_M.spec = {
	-- Options for CluttealTeX
	engine = {
		short = "e",
		long = "engine",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.engine == nil, "multiple --engine options")
			if param is string then
				options.engine = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 1,
			param = "ENGINE",
			text = "TeX engine\n  (Supported: pdflatex, pdftex, lualatex, luatex, luajittex, xelatex, xetex,\n   latex, etex, tex, platex, eptex, ptex, uplatex, euptex, uptex)",
		},
	},
	engine_executable = {
		long = "engine-executable",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.engine_executable == nil, "multiple --engine-executable options")
			if param is string then
				options.engine_executable = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 2,
			param = "COMMAND+OPTIONs",
			text = "TeX command [initial: ENGINE]",
		},
	},
	quiet = {
		long = "quiet",
		param = true,
		default = "1",
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.quiet == nil, "multiple --quiet options")
			if param is string then
				options.quiet = assert(tonumber(param) as integer, "parameter must be an integer")
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.tex_injection[assert(option_t.hook_prios.tex_injection.quiet)] = {typeset_hooks.quiet, "quiet"}
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 3,
			param = "LEVEL",
			text = "Reduce output from TeX command (Supported: 0, 1, 2) [initial: 0]",
		},
	},
	output = {
		short = "o",
		long = "output",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.output == nil, "multiple --output options")
			if param is string then
				options.output = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 4,
			param = "FILE",
			text = "Output filename [initial: JOBNAME.pdf/dvi]",
		},
	},
	fresh = {
		long = "fresh",
		boolean = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.fresh == nil, "multiple --fresh options")
			if param is boolean then
				options.fresh = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 5,
			text = "Clean output directory before running TeX. Rules out --output-directory",
		},
	},
	max_iterations = {
		long = "max-iterations",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.max_iterations == nil, "multiple --max-iterations options")
			options.max_iterations = assert(tonumber(param) as integer, "invalid value for --max-iterations option")
			assert(options.max_iterations >= 1, "invalid value for --max-iterations option")
		end,
		help = {
			ordering = 6,
			param = "N",
			text = "Max number of TeX runs [initial: 3]",
		},
	},
	skip_first = {
		long = "skip-first",
		boolean = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.skip_first == nil, "multiple --skip-first options")
			if param is boolean then
				options.skip_first = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 7,
			text = "Skip running TeX when already up-to-date [initial: false]",
		},
	},
	start_with_draft = {
		boolean = true,
		long = "start-with-draft",
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.start_with_draft == nil, "multiple --start-with-draft options")
			if param is boolean then
				options.start_with_draft = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 8,
			text = "Start with draft mode [initial: false]",
		},
	},
	change_directory = {
		long = "change-directory",
		boolean = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.change_directory == nil, "multiple --change-directory options")
				if param is boolean then
					options.change_directory = param
					else
					error("invalid param type")
				end
			end,
		help = {
			ordering = 9,
			text = "Change directory before running TeX [initial: false]",
		},
	},
	watch = {
		long = "watch",
		param = true,
		default = "auto",
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.watch == nil, "multiple --watch options")
			if param is string then
				options.watch = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 10,
			param = "ENGINE",
			text = "Watch input files for change (Supported: auto, fswatch, inotifywait)\n[initial: auto]",
		},
	},
	watch_only_path = {
		long = "watch-only-path",
		param = true,
		no_cfg = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.watch_inc_exc = options.watch_inc_exc or {}
				table.insert(options.watch_inc_exc, {param=pathutil.abspath(param),type='only_path'})
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 11,
			param = "PATH",
			text = "Add filter to which files are being watched",
		},
	},
	watch_not_path = {
		long = "watch-not-path",
		param = true,
		no_cfg = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.watch_inc_exc = options.watch_inc_exc or {}
				table.insert(options.watch_inc_exc, {param=pathutil.abspath(param),type='not_path'})
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 12,
			param = "PATH",
			text = "Add filter to which files are not being watched",
		},
	},
	watch_only_ext = {
		long = "watch-only-ext",
		param = true,
		no_cfg = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.watch_inc_exc = options.watch_inc_exc or {}
				table.insert(options.watch_inc_exc, {param=param,type='only_ext'})
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 13,
			param = "EXT",
			text = "Add filter to which extensions are being watched",
		},
	},
	watch_not_ext = {
		long = "watch-not-ext",
		param = true,
		no_cfg = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.watch_inc_exc = options.watch_inc_exc or {}
				table.insert(options.watch_inc_exc, {param=param,type='not_ext'})
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 14,
			param = "PATH",
			text = "Add filter to which extensions are not being watched",
		},
	},
	watch_inc_exc = {
		no_cli = true,
		accumulate = true,
		handle_cfg = function(options:option_t.Options, param: {any})
			for _,i in ipairs(param) do
				if i is option_t.WatchIncExc then
					if i.type and i.param and (i.type == "not_ext" or i.type == "only_ext" or i.type == "not_path" or i.type == "only_path") then
						table.insert(options.watch_inc_exc, i)
					end
				end
			end
		end,
	},
	makeindex = {
		long = "makeindex",
		param = true,
		default = "makeindex",
		suggestion_handlers = {
			execlog_based = function(o:option_t.Options)
				o.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.makeindex)] = {
					function(execlog:string, _:option_t.Options): boolean
						return string.find(execlog, "No file [^\n]+%.ind%.") ~= nil
					end,
					"You may want to use --makeindex option."
				}
			end
		},
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(not options.glossaries, "'makeindex' cannot be used together with 'glossaries'\nUse e.g. --glossaries='makeindex:ind:idx:ilg' instead of makeindex")
			assert(options.makeindex == nil, "multiple --makeindex options")
			if param is string then
				options.makeindex = param
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.makeindex)] = {typeset_hooks.makeindex, "makeindex"}
				options.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.makeindex)] = nil
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 17,
			param = "COMMAND+OPTIONs",
			text = "Run makeindex (provide command for generation)",
		},
	},
	glossaries = {
		long = "glossaries",
		param = true,
		accumulate = true,
		default = "makeindex:glo:gls:glg",
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(not options.makeindex, "'glossaries' cannot be used together with 'makeindex'\nUse e.g. --glossaries='makeindex:ind:idx:ilg' instead of makeindex")
			if not options.glossaries then
				options.glossaries = {}
			end
			if param is string then
				options.glossaries = options.glossaries or {}
				table.insert(options.glossaries, assert(parse_glossaries_option_from_string(param)))
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.glossaries)] = {typeset_hooks.glossaries, "glossaries"}
			else
				error("invalid param type")
			end
		end,
		handle_cfg = function(options:option_t.Options, param: table)
			local param = (function(): {string:string|nil}
				local inp = param.inp
				if not inp is string and not inp is nil then
					return
				end

				local t = param.type
				if not t is string and not t is nil then
					return
				end

				local out = param.out
				if not out is string and not out is nil then
					return
				end

				local path = param.path
				if not path is string and not path is nil then
					return
				end

				local cmd = param.cmd
				if not cmd is string and not cmd is nil then
					return
				end

				local log = param.log
				if not log is string and not log is nil then
					return
				end
				return {type=t, out=out, inp=inp, log=log, path=path, cmd=cmd}
			end)()

			options.glossaries = options.glossaries or {}
			table.insert(options.glossaries, assert(parse_glossaries_option_from_table(param)))
			if not options.hooks then _M.init_hooks(options) end
			options.hooks.post_compile[assert(option_t.hook_prios.post_compile.glossaries)] = {typeset_hooks.glossaries, "glossaries"}
		end,
		help = {
			ordering = 18,
			param = "type:outputFile:inputFile:logFile:pathToCommand:commandArgs",
			text = "Configure a specific index (needed e.g. for abbreviations)",
			longLine = true,
		},
	},
	bibtex = {
		long = "bibtex",
		param = true,
		default = "bibtex",
		suggestion_handlers = {
			execlog_based = function(o:option_t.Options)
				o.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.bibtex)] = {
					function(execlog:string, o:option_t.Options): boolean
						return string.find(execlog, "No file [^\n]+%.bbl%.") ~= nil and not o.biber
					end,
					"You may want to use --bibtex or --biber option."
				}
			end
		},
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.bibtex == nil, "multiple --bibtex options")
			assert(options.biber == nil, "multiple --bibtex/--biber options")
			if param is string then
				options.bibtex = param
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.bibtex)] = {typeset_hooks.bibtex, "bibtex"}
				options.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.bibtex)] = nil
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 19,
			param = "COMMAND+OPTIONs",
			text = "Run bibtex (provide command for generation)",
		},
	},
	biber = {
		long = "biber",
		param = true,
		default = "biber",
		suggestion_handlers = {
			execlog_based = function(o:option_t.Options)
				o.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.biber)] = {
					function(execlog:string, o:option_t.Options): boolean
						return string.find(execlog, "No file [^\n]+%.bbl%.") ~= nil and not o.bibtex
					end,
					"You may want to use --bibtex or --biber option."
				}
			end
		},
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.biber == nil, "multiple --biber options")
			assert(options.bibtex == nil, "multiple --bibtex/--biber options")
			if param is string then
				options.biber = param
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.biber)] = {typeset_hooks.biber, "biber"}
				options.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.biber)] = nil
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 20,
			param = "COMMAND+OPTIONs",
			text = "Run biber (provide command for generation)",
		},
	},
	sagetex = {
		long = "sagetex",
		param = true,
		default = "sage",
		suggestion_handlers = {
			execlog_based = function(o:option_t.Options)
				o.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.sagetex)] = {
					function(execlog:string, _:option_t.Options): boolean
						return string.find(execlog, "Run Sage on") ~= nil
					end,
					"You may want to use --sagetex option."
				}
			end
		},
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.sagetex == nil, "multiple --sagetex options")
			if param is string then
				options.sagetex = param
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.sagetex)] = {typeset_hooks.sagetex, "sagetex"}
				options.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.sagetex)] = nil
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 21,
			param = "COMMAND+OPTIONs",
			text = "Run sage (provide command for generation)",
		},
	},
	memoize = {
		long = "memoize",
		param = true,
		default = "perl",
		suggestion_handlers = {
			execlog_based = function(o:option_t.Options)
				o.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.memoize)] = {
					function(execlog:string, _:option_t.Options): boolean
						return string.find(execlog, "Package memoize Warning") ~= nil
					end,
					"You may want to use --memoize option."
				}
			end
		},
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.memoize == nil, "multiple --memoize options")
			if param is string then
				if param == "python" then
					options.memoize = "memoize-extract.py"
				elseif param == "perl" then
					options.memoize = "memoize-extract.pl"
				else
					options.memoize = param
				end
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.tex_injection[assert(option_t.hook_prios.tex_injection.memoize+0.1)] = {typeset_hooks.memoize, "memoize"}
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.memoize)] = {typeset_hooks.memoize_run, "memoize"}
				options.hooks.suggestion_execlog_based[assert(option_t.hook_prios.suggestion_execlog_based.memoize)] = nil
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 22,
			param = "TYPE",
			text = "Run memoize (supports: python, pearl or specifying a custom path)",
		},
	},
	memoize_opt = {
		long = "memoize-opt",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.memoize_opts = options.memoize_opts or {}
				table.insert(options.memoize_opts, param)
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.tex_injection[assert(option_t.hook_prios.tex_injection.memoize-0.2)] = {typeset_hooks.memoize_opts, "memoize_opts"}
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 23,
			param = "PACKAGE_OPT",
			text = "Pass more package options to the memoize package",
		},
	},
	help = {
		short = "h",
		long = "help",
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			_M.usage(arg)
			os.exit(0)
		end,
		help = {
			ordering = 25,
			text = "Print this help output and exit",
		},
	},
	version = {
		short = "v",
		long = "version",
		handle_cli = function(options:option_t.Options, param:string|boolean)
			io.stderr:write("cluttealtex ",CLUTTEALTEX_VERSION,"\n")
			os.exit(0)
		end,
		help = {
			ordering = 26,
			text = "Print version information and exit",
		},
	},
	verbose = {
		short = "V",
		long = "verbose",
		accumulate = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			CLUTTEALTEX_VERBOSITY = CLUTTEALTEX_VERBOSITY + 1
		end,
		help = {
			ordering = 27,
			text = "Be more verbose (can be passed multiple times)",
		},
	},
	color = {
		long = "color",
		param = true,
		default = "always",
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.color == nil, "multiple --color options")
			if param is string then
				options.color = param
			else
				error("invalid param type")
			end
			message.set_colors(options.color)
		end,
		help = {
			ordering = 28,
			param = "WHEN",
			text = "When should CluttealTeX print in color? (Supported: always, auto, never)\n  [initial: auto]",
		},
	},
	includeonly = {
		long = "includeonly",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.includeonly == nil, "multiple --includeonly options")
			if param is string then
				options.includeonly = param
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.tex_injection[assert(option_t.hook_prios.tex_injection.includeonly)] = {typeset_hooks.includeonly, "includeonly"}
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 30,
			param = "NAMEs",
			text = "Inject '\\includeonly{NAMEs}'",
		},
	},
	make_depends = {
		long = "make-depends",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.make_depends == nil, "multiple --make-depends options")
			if param is string then
				options.make_depends = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 31,
			param = "FILE",
			text = "Write dependencies as a Makefile rule to FILE",
		},
	},
	print_output_directory = {
		long = "print-output-directory",
		boolean = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.print_output_directory == nil, "multiple --print-output-directory options")
			if param is boolean then
				options.print_output_directory = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 32,
			text = "Print the output directory and exit",
		},
	},
	package_support = {
		long = "package-support",
		param = true,
		accumulate = true,
		suggestion_handlers = {
			file_based = function(o:option_t.Options)
				o.hooks.suggestion_file_based[assert(option_t.hook_prios.suggestion_file_based.package_support)+0.1] = {
					function(fileinfo:common_t.Filemap_ele): boolean
							return string.find(fileinfo.path, "minted/minted%.sty$") ~= nil
					end,
					"You may want to use --package-support=minted option."
				}
				o.hooks.suggestion_file_based[assert(option_t.hook_prios.suggestion_file_based.package_support)+0.2] = {
					function(fileinfo:common_t.Filemap_ele): boolean
							return string.find(fileinfo.path, "epstopdf%.sty$") ~= nil
					end,
					"You may want to use --package-support=epstopdf option."
				}
			end
		},
		handle_cli = function(options:option_t.Options, param:string|boolean)
			local known_packages:{string:function(option_t.Options)} = {
				-- minted uses offset 0.1 in hooks
				minted = function(o: option_t.Options)
					if not o.hooks then _M.init_hooks(o) end
					o.hooks.tex_injection[assert(option_t.hook_prios.tex_injection.package_support)+0.1] = {typeset_hooks.ps_minted, "package_support minted"}
					o.hooks.suggestion_file_based[assert(option_t.hook_prios.suggestion_file_based.package_support)+0.1] = nil
				end,
				-- epstopdf uses offset 0.2 in hooks
				epstopdf = function(o: option_t.Options)
					if not o.hooks then _M.init_hooks(o) end
					o.hooks.tex_injection[assert(option_t.hook_prios.tex_injection.package_support)+0.2] = {typeset_hooks.ps_epstopdf, "package_support epstopdf"}
					o.hooks.suggestion_file_based[assert(option_t.hook_prios.suggestion_file_based.package_support)+0.2] = nil
				end,
			}
			if param is string then
				for pkg in string.gmatch(param, "[^,%s]+") do
					options.package_support[pkg] = true
					if known_packages[pkg] then
						-- register the corresponding hook
						known_packages[pkg](options)
					elseif CLUTTEALTEX_VERBOSITY >= 1 then
						message.warn("CluttealTeX provides no special support for '"..pkg.."'.")
					end
				end
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 33,
			param = "PKG1,...",
			text = "Special support for some packages (Supported: minted, epstopdf)",
		},
	},
	check_driver = {
		long = "check-driver",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.check_driver == nil, "multiple --check-driver options")
			assert(param == "dvipdfmx" or param == "dvips" or param == "dvisvgm", "wrong value for --check-driver option")
			if param is string then
				options.check_driver = param
				if not options.hooks then _M.init_hooks(options) end
				options.hooks.post_compile[assert(option_t.hook_prios.post_compile.check_driver)] = {typeset_hooks.check_driver, "check_driver"}
			else
				assert(param is string, "invalid param type")
			end
		end,
		help = {
			ordering = 34,
			param = "DRIVER",
			text = "Check the correct driver file is loaded (Supported: dvipdfmx, dvips, dvisvgm)",
		},
	},
	-- Options for TeX
	shell_escape = {
		long = "shell-escape",
		boolean = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.shell_escape == nil and options.shell_restricted == nil, "multiple --(no-)shell-escape or --shell-restricted options")
			if param is boolean then
				options.shell_escape = param
			else
				assert(param is string, "invalid param type")
			end
		end,
		help = {
			ordering = 35,
			text = "",
		},
	},
	shell_restricted = {
		long = "shell-restricted",
		allow_single_hyphen = true,
		-- not a boolean option!
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.shell_escape == nil and options.shell_restricted == nil, "multiple --(no-)shell-escape or --shell-restricted options")
			options.shell_restricted = true
		end,
		help = {
			ordering = 36,
			text = "",
		},
	},
	synctex = {
		long = "synctex",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.synctex == nil, "multiple --synctex options")
			if param is string then
				options.synctex = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 37,
			param = "NUMBER",
			text = "", -- TODO
		},
	},
	fmt = {
		long = "fmt",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.fmt == nil, "multiple --fmt options")
			if param is string then
				options.fmt = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 38,
			param = "FMTNAME",
			text = "",
		},
	},
	file_line_error = {
		long = "file-line-error",
		boolean = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is boolean then
				options.file_line_error = param
			else
				assert(param is string, "invalid param type")
			end
		end,
		help = {
			ordering = 39,
			text = "[initial: true]",
		},
	},
	halt_on_error = {
		long = "halt-on-error",
		boolean = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is boolean then
				options.halt_on_error = param
			else
				assert(param is string, "invalid param type")
			end
		end,
		help = {
			ordering = 40,
			param = "COMMAND+OPTIONs",
			text = "[initial: true]",
		},
	},
	interaction = {
		long = "interaction",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.interaction == nil, "multiple --interaction options")
			if param is string then
				assert(param == "batchmode" or param == "nonstopmode" or param == "scrollmode" or param == "errorstopmode", "invalid argument for --interaction")
				options.interaction = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 41,
			param = "STRING",
			text = "[initial: nonstopmode]",
		},
	},
	jobname = {
		long = "jobname",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.jobname == nil, "multiple --jobname options")
			if param is string then
				options.jobname = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 42,
			param = "JOBNAME",
			text = "",
		},
	},

	output_directory = {
		long = "output-directory",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.output_directory == nil, "multiple --output-directory options")
			if param is string then
				options.output_directory = param
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 43,
			param = "DIR",
			text = "Where to produce the outputs [initial: somewhere a temp dir]",
		},
	},
	output_format = {
		long = "output-format",
		param = true,
		allow_single_hyphen = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			assert(options.output_format == nil, "multiple --output-format options")
			assert(param == "pdf" or param == "dvi", "invalid argument for --output-format")
			if param is string then
				options.output_format = param
			else
				assert(param is string, "invalid param type")
			end
		end,
		help = {
			ordering = 44,
			param = "FORMAT",
			text = "Supported: pdf, dvi [initial: pdf]",
		},
	},
	tex_option = {
		long = "tex-option",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.tex_extraoptions = options.tex_extraoptions or {}
				table.insert(options.tex_extraoptions, shellutil.escape(param))
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 45,
			param = "OPTION",
			text = "Pass OPTION to TeX as a single option",
		},
	},
	tex_options = {
		long = "tex-options",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.tex_extraoptions = options.tex_extraoptions or {}
				table.insert(options.tex_extraoptions, param)
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 46,
			param = "OPTIONs",
			text = "Pass OPTIONs to TeX as multiple options.",
		},
	},
	dvipdfmx_option = {
		long = "dvipdfmx-option",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.dvipdfmx_extraoptions = options.dvipdfmx_extraoptions or {}
				table.insert(options.dvipdfmx_extraoptions, shellutil.escape(param))
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 47,
			param = "OPTION",
			text = "Same for dvipdfmx.",
		},
	},
	dvipdfmx_options = {
		long = "dvipdfmx-options",
		param = true,
		handle_cli = function(options:option_t.Options, param:string|boolean)
			if param is string then
				options.dvipdfmx_extraoptions = options.dvipdfmx_extraoptions or {}
				table.insert(options.dvipdfmx_extraoptions, param)
			else
				error("invalid param type")
			end
		end,
		help = {
			ordering = 48,
			param = "OPTIONs",
			text = "Same for dvipdfmx.",
		},
	},
}

local record outRec
	short:    string
	long:     string
	text:     string
	longLine: boolean
	ordering: number
end
local record alignRec
	short:    integer
	long:     integer
	ordering: number
end

local function usage_ele(optname:string, opt:Option, alignment:alignRec):outRec
	if not opt.long and not opt.short then
		return nil
	end
	opt.help = opt.help or {text="", param=optname, ordering=nil, longLine=false}
	local long:string = ""
	if opt.long then
		if opt.boolean then
			long = "--[no-]"..opt.long
		else
			long = "--"..opt.long
		end
		if opt.param and opt.default then
			long = long.."[="..opt.help.param.."]"
		elseif opt.param then
			long = long.."="..opt.help.param
		end
	end

	local short:string = "  "
	if opt.short then
		short = "-"..opt.short
	end

	if long ~= "" and short ~= "  " then
		short = short..","
	else
		short = short.." "
	end

	if not opt.help.longLine then
		alignment.long  = math.max(alignment.long, #long+2)
	end
	alignment.short = math.max(alignment.short, #short+1)

	if opt.help.ordering then
		alignment.ordering = math.max(alignment.ordering, opt.help.ordering)
	end

	return {
		short    = short,
		long     = long,
		text     = opt.help.text,
		longLine = opt.help.longLine,
		ordering = opt.help.ordering,
	}
end

function _M.usage(arg:{string})
	local alignment = {
		short    = 0,
		long     = 0,
		ordering = 0,
	}
	local output:{outRec} = {}
	for optname, opt in pairs(_M.spec) do
		local x = usage_ele(optname, opt, alignment)
		local _ = x and table.insert(output, x)
	end

	do
		local i = alignment.ordering+1
		for j,k in ipairs(output) do
			if not k.ordering then
				output[j].ordering = i
				i = i+1
			end
		end
	end
	alignment.short = 4

	table.sort(output, function(a:outRec,b:outRec):boolean return a.ordering < b.ordering end)

	io.write(([[CluttealTeX: Process TeX files without cluttering your working directory

Usage:
  %s [options] [--] FILE.tex

Options:
]]):format(arg[0] or "texlua cluttealtex.lua"))
	local last_order = 0.0
	for _,opt in ipairs(output) do
		local short = opt.short
		short = short..(" "):rep(alignment.short - #short)

		local long = opt.long
		local text = opt.text
		if opt.longLine then
			text = "\n"..text
		else
			long = long..(" "):rep(alignment.long - #long)
		end
		text = text:gsub("\n", "\n"..(" "):rep(2+alignment.short+alignment.long))

		if math.abs(last_order - opt.ordering) > 1 then
			io.write("\n")
		end
		io.write(("  %s%s%s\n"):format(short, long, text))

		last_order = opt.ordering
	end
	io.write("\n\n", ([[For a more detailed reference see 'texdoc cluttealtex' or
    'https://github.com/atticus-sullivan/cluttealtex/releases/download/%s/cluttealtex.pdf'

When run, cluttealtex checks for a config file named '.cluttealtexrc.lua' in your current working directory
(see the detailed docs for more information on how this works)
]]):format(CLUTTEALTEX_VERSION))
end


if CLUTTEALTEX_TEST_ENV then
	_M._internal = {
		split                               = split,
		parse_glossaries_option_from_table  = parse_glossaries_option_from_table,
		parse_glossaries_option_from_string = parse_glossaries_option_from_string,
		usage_ele                           = usage_ele,
	}
end

return _M
