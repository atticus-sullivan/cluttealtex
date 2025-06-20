-- SPDX-FileCopyrightText: 2016 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- External libraries (included in texlua)
local md5     = require "md5"

local os                           = require"os_"
local pathutil                     = require "texrunner.pathutil"
local shellutil                    = require "texrunner.shellutil"
local options                      = require "texrunner.option_type" -- legacy import
local message                      = require "texrunner.message"
local reruncheck                   = require "texrunner.reruncheck"
local fsutil                       = require "texrunner.fsutil"
local engine_t                     = require "texrunner.tex_engine"
local extract_bibtex_from_aux_file = require "texrunner.auxfile".extract_bibtex_from_aux_file
local safename                     = require "texrunner.safename"
local recoverylib                  = require "texrunner.recovery"

local common_t                     = require "texrunner.common_types"
local ts_hooks                     = require "texrunner.typeset_hooks"

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end

local record Module
	get_typesetter: function(args: Module.typesetArgs): (function(): boolean, string, integer, {common_t.Filemap_ele})
	record typesetArgs
		auxstatus:{string:common_t.Status}
		iteration:integer
		path_in_output_directory: function(string): string
		recorderfile: string
		recorderfile2: string
		engine: engine_t.Engine
		options: options.Options
		output_extension: string
		inputfile: string
		tex_options:engine_t.Option
		original_wd: string
	end
end

-- Run TeX command (*tex, *latex)
-- should_rerun, newauxstatus = single_run([auxstatus])
-- This function should be run in a coroutine.
local function single_run_coroutine(args: Module.typesetArgs): boolean|string
	local bibtex_aux_hash:string = nil
	local mainauxfile = args.path_in_output_directory("aux")
	if fsutil.isfile(args.recorderfile) then
		-- Recorder file already exists
		local filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile, args.options)
		if args.engine.is_luatex and fsutil.isfile(args.recorderfile2) then
			filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile2, args.options, filelist, filemap)
		end
		args.auxstatus = reruncheck.collectfileinfo(filelist, args.auxstatus)

		-- emits suggestsions to the user which options might be usefull
		-- does nothing except potentially message.diag -> no return needed
		ts_hooks.apply_suggestion_file_based(args.options.hooks.suggestion_file_based, filelist)

		if args.options.bibtex then
			local biblines = extract_bibtex_from_aux_file(mainauxfile, args.options.output_directory)
			if #biblines > 0 then
				bibtex_aux_hash = md5.sum(table.concat(biblines, "\n"))
			end
		end
		if args.iteration == 1 and not args.options.watch then
			if not reruncheck.anyNonOutputNewerThan(filelist, args.options.outfile) then
				return false
			end
		end
	else
		-- This is the first execution
		if args.auxstatus ~= nil then
			message.error("Recorder file was not generated during the execution!")
			os.exit(1)
		end
		args.auxstatus = {}
	end

	local tex_injection = args.tex_options.tex_injection or ""

	-- run tex_injection hooks
	tex_injection = ts_hooks.apply_tex_injection(args.options.hooks.tex_injection, args.options, args.tex_options, tex_injection)

	local inputline = tex_injection .. safename.safeinput(args.inputfile, args.engine)

	local current_tex_options, lightweight_mode = args.tex_options, false
	if args.iteration == 1 and args.options.start_with_draft then
		current_tex_options = {}
		for k,v in pairs(args.tex_options as {string:any}) do
			(current_tex_options as {string:any})[k] = v
		end
		if args.engine.supports_draftmode then
			current_tex_options.draftmode = true
			args.options.start_with_draft = false
		end
		current_tex_options.interaction = "batchmode"
		lightweight_mode = true
	else
		current_tex_options.draftmode = false
	end

	local command = args.engine:build_command(inputline, current_tex_options)

	local execlog:string -- the contents of .log file

	local recovered = false
	local function recover(): boolean
		-- Check log file
		if not execlog then
			local logfile = assert(io.open(args.path_in_output_directory("log")))
			execlog = logfile:read("*a")
			logfile:close()
		end
		recovered = recoverylib.try_recovery{
			execlog = execlog,
			auxfile = args.path_in_output_directory("aux"),
			options = options,
			original_wd = args.original_wd,
		}
		return recovered
	end
	coroutine.yield(command, recover) -- Execute the command
	if recovered then
		return true
	end

	local filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile, args.options)
	if args.engine.is_luatex and fsutil.isfile(args.recorderfile2) then
		filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile2, args.options, filelist, filemap)
	end

	if not execlog then
		local logfile = assert(io.open(args.path_in_output_directory("log")))
		execlog = logfile:read("*a")
		logfile:close()
	end

	ts_hooks.apply_post_compile(args.options.hooks.post_compile, args.options, {
		filelist                 = filelist,
		auxstatus                = args.auxstatus,
		path_in_output_directory = args.path_in_output_directory,
		bibtex_aux_hash          = bibtex_aux_hash,
		original_wd              = args.original_wd,
	})

	ts_hooks.apply_suggestion_excelog_based(args.options.hooks.suggestion_execlog_based, execlog, args.options)

	if string.find(execlog, "No pages of output.") then
		return "No pages of output."
	end

	local should_rerun: boolean
	should_rerun, args.auxstatus = reruncheck.comparefileinfo(filelist, args.auxstatus)
	return should_rerun or lightweight_mode
end

-- Run (La)TeX (possibly multiple times) and produce a PDF file.
-- This function should be run in a coroutine.
local function do_typeset_coroutine(args:Module.typesetArgs): string, function
	local iteration = 0
	local should_rerun: boolean|string
	repeat
		iteration = iteration + 1
		should_rerun = single_run_coroutine(args)
		if should_rerun == "No pages of output." then
			message.warn("No pages of output.")
			return
		end
	until not should_rerun or iteration >= args.options.max_iterations

	if should_rerun then
		message.warn("LaTeX should be run once more.")
	end

	-- Successful
	if args.options.output_format == "dvi" or args.engine.supports_pdf_generation then
		-- Output file (DVI/PDF) is generated in the output directory
		local oncopyerror:function():boolean
		if os.type == "windows" then
			oncopyerror = function(): boolean
				message.error("Failed to copy file.  Some applications may be locking the ", string.upper(args.options.output_format), " file.")
				return false
			end
		end
		coroutine.yield(fsutil.copy_command(args.options.outfile, args.options.output), oncopyerror)
		if #args.options.dvipdfmx_extraoptions > 0 then
			message.warn("--dvipdfmx-option[s] are ignored.")
		end

	else
		-- DVI file is generated, but PDF file is wanted
		local dvifile = args.path_in_output_directory("dvi")
		local dvipdfmx_command = {"dvipdfmx", "-o", shellutil.escape(args.options.output)}
		for _,v in ipairs(args.options.dvipdfmx_extraoptions) do
			table.insert(dvipdfmx_command, v)
		end
		table.insert(dvipdfmx_command, shellutil.escape(dvifile))
		coroutine.yield(table.concat(dvipdfmx_command, " "))
	end

	-- Copy SyncTeX file if necessary
	if args.options.output_format == "pdf" then
		local synctex = tonumber(args.options.synctex or "0")
		local synctex_ext:string = nil
		if synctex > 0 then
			-- Compressed SyncTeX file (.synctex.gz)
			synctex_ext = "synctex.gz"
		elseif synctex < 0 then
			-- Uncompressed SyncTeX file (.synctex)
			synctex_ext = "synctex"
		end
		if synctex_ext then
			coroutine.yield(fsutil.copy_command(args.path_in_output_directory(synctex_ext), pathutil.replaceext(args.options.output, synctex_ext)))
		end
	end

	-- Write dependencies file
	if args.options.make_depends then
		local filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile, args.options)
		if args.engine.is_luatex and fsutil.isfile(args.recorderfile2) then
			filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile2, args.options, filelist, filemap)
		end
		local f = assert(io.open(args.options.make_depends, "w"))
		f:write(args.options.output, ":")
		for _,fileinfo in ipairs(filelist) do
			if fileinfo.kind == "input" then
				f:write(" ", fileinfo.path)
			end
		end
		f:write("\n")
		f:close()
	end

	ts_hooks.apply_post_build(args.options.hooks.post_build, args.options)
end

local function do_typeset(args: Module.typesetArgs): boolean, string, integer
	-- Execute the command string yielded by do_typeset_c
	for command, recover in coroutine.wrap(function():(string, function) return do_typeset_coroutine(args) end) do
		if command is string and (recover is function or recover is nil) then
			message.exec(command)
			local success, termination, status_or_signal = os.execute(command)
			if success ~= 0 and not (recover and (recover as function)()) then
				if termination == "exit" then
					message.error("Command exited abnormally: exit status ", tostring(status_or_signal))
				elseif termination == "signal" then
					message.error("Command exited abnormally: signal ", tostring(status_or_signal))
				else
					message.error("Command exited abnormally: ", tostring(status_or_signal))
				end
				return false, termination, status_or_signal
			end
		else
			error(string.format("invalid type. command: %s recover: %s", type(command), type(recover)))
		end
	end
	-- Successful
	if CLUTTEALTEX_VERBOSITY >= 1 then
		message.info("Command exited successfully")
	end
	return true
end

local function get_typesetter(args: Module.typesetArgs): (function(): boolean, string, integer, {common_t.Filemap_ele})
	local filelist, filemap: {common_t.Filemap_ele}, {string: common_t.Filemap_ele}
	return function(): boolean, string, integer, {common_t.Filemap_ele}
		local success, termination, status = do_typeset(args)
		-- TODO: filenames here can be UTF-8 if command_line_encoding=utf-8

		filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile, options)
		if args.engine.is_luatex and fsutil.isfile(args.recorderfile2) then
			filelist, filemap = reruncheck.parse_recorder_file(args.recorderfile2, options, filelist, filemap)
		end

		return success, termination, status, filelist
	end
end

local _M:Module = {
	get_typesetter = get_typesetter
}

return _M
