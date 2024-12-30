--[[
Copyright 2016 ARATA Mizuki
Copyright 2024 Lukas Heindl

This file is part of CluttealTeX.

CluttealTeX is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

CluttealTeX is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with CluttealTeX.  If not, see <http://www.gnu.org/licenses/>.
]]

-- External libraries (included in texlua)
local md5     = require "md5"
local filesys = require "lfs"

local os                           = require"os_"
local pathutil                     = require "texrunner.pathutil"
local checkdriver                  = require "texrunner.checkdriver".checkdriver
local shellutil                    = require "texrunner.shellutil"
local options                      = require "texrunner.option_type" -- legacy import
local message                      = require "texrunner.message"
local reruncheck                   = require "texrunner.reruncheck"
local fsutil                       = require "texrunner.fsutil"
local engine_t                     = require "texrunner.tex_engine"
local extract_bibtex_from_aux_file = require "texrunner.auxfile".extract_bibtex_from_aux_file
local safename                     = require "texrunner.safename"
local recoverylib                  = require "texrunner.recovery"

local option_t                     = require "texrunner.option_type"
local common_t                     = require "texrunner.common_types"

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
		auxstatus:{string:reruncheck.Status}
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

local function hooks_sort_prios(hook_table: {number: {function, string}}): {number}
	local priorities = {}
	for prio in pairs(hook_table) do
		table.insert(priorities, prio)
	end
	table.sort(priorities)
	return priorities
end

local function hooks_validate(hook: {function, string, boolean}): boolean, string
	if not hook or not hook[1] or not hook[2] then
		return false, "Malformed hook"
	end
	return true, nil
end

-- returns the new tex_injection string
local function hooks_apply_tex_injection(hooks: {number: {(function(option_t.Options, engine_t.Option, string):string), string}}, options: option_t.Options, tex_options: engine_t.Option, tex_injection:string): string
	local sorted_prios = hooks_sort_prios(hooks as {number: {function, string}})
	local result = tex_injection
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = hooks_validate(hook)
		if not valid then
			error("Invalid hook: " .. err)
		end
		result = hook[1](options, tex_options, result)
		 if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("Executing tex_injection hook '", hook[2], "'")
		end
	end
	return result
end

local function hooks_apply_suggestion_file_based(hooks: {number: {(function(common_t.Filemap_ele):boolean), string, boolean}}, filelist:{common_t.Filemap_ele})
	local sorted_prios = hooks_sort_prios(hooks as {number: {function, string}})
	-- check if all hooks are valid
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = hooks_validate(hook)
		if not valid then
			error("Invalid hook: " .. err)
		end
	end

	-- run hooks on files contained in the filelist and emit messages
	for _,fileinfo in ipairs(filelist) do
		for _, prio in ipairs(sorted_prios) do
			local hook = hooks[prio]
			if not hook[3] and hook[1](fileinfo) then
				message.diag(hook[2])
				hook[3] = true
			end
		end
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
		hooks_apply_suggestion_file_based(args.options.hooks.suggestion_file_based, filelist)

		if args.options.bibtex then
			local biblines = extract_bibtex_from_aux_file(mainauxfile, args.options.output_directory)
			if #biblines > 0 then
				bibtex_aux_hash = md5.sum(table.concat(biblines, "\n"))
			end
		end
		if args.iteration == 1 and not args.options.watch then
			local outfile = args.path_in_output_directory(args.output_extension)
			if not reruncheck.anyNonOutputNewerThan(filelist, outfile) then
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
	tex_injection = hooks_apply_tex_injection(args.options.hooks.tex_injection, args.options, args.tex_options, tex_injection)

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

	if args.options.check_driver ~= nil then
		checkdriver(args.options.check_driver, filelist)
	end

	if args.options.makeindex then
		-- Look for .idx files and run MakeIndex
		for _,file in ipairs(filelist) do
			if pathutil.ext(file.path) == "idx" then
				-- Run makeindex if the .idx file is new or updated
				local idxfileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				local output_ind = pathutil.replaceext(file.abspath, "ind")
				if reruncheck.comparefileinfo({idxfileinfo}, args.auxstatus) or reruncheck.comparefiletime(file.abspath, output_ind, args.auxstatus) then
					local idx_dir = pathutil.dirname(file.abspath)
					local makeindex_command = {
						"cd", shellutil.escape(idx_dir), "&&",
						args.options.makeindex, -- Do not escape options.makeindex to allow additional options
						"-o", pathutil.basename(output_ind),
						pathutil.basename(file.abspath)
					}
					coroutine.yield(table.concat(makeindex_command, " "))
					table.insert(filelist, {path = output_ind, abspath = output_ind, kind = "auxiliary"})
				else
					local succ, err = filesys.touch(output_ind)
					if not succ then
						message.warn("Failed to touch " .. output_ind .. " (" .. err .. ")")
					end
				end
			end
		end
	else
		-- Check log file
		if string.find(execlog, "No file [^\n]+%.ind%.") then
			message.diag("You may want to use --makeindex option.")
		end
	end

	if args.options.glossaries then
		-- Look for configured files and run makeindex/xindy
		for _,file in ipairs(filelist) do
			for _, cfg in ipairs(args.options.glossaries) do
				if pathutil.ext(file.path) == cfg.inp then
					-- Run xindy/makeindex if the specified input-file is new or updated
					local inputfileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
					local outputfile = args.path_in_output_directory(cfg.out)
					if reruncheck.comparefileinfo({inputfileinfo}, args.auxstatus) or reruncheck.comparefiletime(file.abspath, outputfile, args.auxstatus) then
						print(cfg.cmd(args.path_in_output_directory))
						coroutine.yield(cfg.cmd(args.path_in_output_directory))
						table.insert(filelist, {path = outputfile, abspath = outputfile, kind = "auxiliary"})
					else
						local succ, err = filesys.touch(outputfile)
						if not succ then
							message.warn("Failed to touch " .. outputfile .. " (" .. err .. ")")
						end
					end
				end
			end
		end
	end

	if args.options.bibtex then
		local biblines2 = extract_bibtex_from_aux_file(mainauxfile, args.options.output_directory)
		local bibtex_aux_hash2: string
		if #biblines2 > 0 then
			bibtex_aux_hash2 = md5.sum(table.concat(biblines2, "\n"))
		end
		local output_bbl = args.path_in_output_directory("bbl")
		if bibtex_aux_hash ~= bibtex_aux_hash2 or reruncheck.comparefiletime(pathutil.abspath(mainauxfile), output_bbl, args.auxstatus) then
			-- The input for BibTeX command has changed...
			-- os.execute("pwd")
			-- os.execute("echo $BIBINPUTS")
			local bibtex_command = {
				"cd", shellutil.escape(args.options.output_directory), "&&",
				args.options.bibtex,
				pathutil.basename(mainauxfile)
			}
			coroutine.yield(table.concat(bibtex_command, " "))
		else
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.info("No need to run BibTeX.")
			end
			local succ, err = filesys.touch(output_bbl)
			if not succ then
				message.warn("Failed to touch " .. output_bbl .. " (" .. err .. ")")
			end
		end
	elseif args.options.biber then
		for _,file in ipairs(filelist) do
			-- usual compilation with biber
			-- tex     -> pdflatex tex -> aux,bcf,pdf,run.xml
			-- bcf     -> biber bcf    -> bbl
			-- tex,bbl -> pdflatex tex -> aux,bcf,pdf,run.xml
			if pathutil.ext(file.path) == "bcf" then
				-- Run biber if the .bcf file is new or updated
				local bcffileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				local output_bbl = pathutil.replaceext(file.abspath, "bbl")
				local updated_dot_bib = false
				-- get the .bib files, the bcf uses as input
				for l in io.lines(file.abspath) do
					local bib = string.match(l, "<bcf:datasource .*>(.*)</bcf:datasource>") -- might be unstable if biblatex adds e.g. a linebreak
					if bib then
						local bibfile = pathutil.join(args.original_wd, bib)
						local succ, err = io.open(bibfile, "r") -- check if file is present, don't use touch to avoid triggering a rerun
						if succ then
							succ:close()
							local updated_dot_bib_tmp = not reruncheck.comparefiletime(pathutil.abspath(mainauxfile), bibfile, args.auxstatus)
							if updated_dot_bib_tmp then
								message.info(bibfile.." is newer than aux")
							end
							updated_dot_bib = updated_dot_bib_tmp or updated_dot_bib
						else
							message.warn(bibfile .. " is not accessible (" .. err .. ")")
						end
					end
				end
				if updated_dot_bib or reruncheck.comparefileinfo({bcffileinfo}, args.auxstatus) or reruncheck.comparefiletime(file.abspath, output_bbl, args.auxstatus) then
					local biber_command = {
						args.options.biber, -- Do not escape options.biber to allow additional options
						"--output-directory", shellutil.escape(args.options.output_directory),
						pathutil.basename(file.abspath)
					}
					coroutine.yield(table.concat(biber_command, " "))
					-- watch for changes in the bbl
					table.insert(filelist, {path = output_bbl, abspath = output_bbl, kind = "auxiliary"})
				else
					local succ, err = filesys.touch(output_bbl)
					if not succ then
						message.warn("Failed to touch " .. output_bbl .. " (" .. err .. ")")
					end
				end
			end
		end
	else
		-- Check log file
		if string.find(execlog, "No file [^\n]+%.bbl%.") then
			message.diag("You may want to use --bibtex or --biber option.")
		end
	end

	if args.options.memoize then
		for _,file in ipairs(filelist) do
			-- usual compilation with memoize
			-- tex      -> pdflatex tex    -> aux,pdf,mmz
			-- mmz,pdf  -> memoize-extract -> pdf,pdf
			-- tex      -> pdflatex tex    -> aux,pdf
			if pathutil.ext(file.path) == "mmz" then
				local must_extract = false
				for l in io.lines(file.abspath) do
					local newExtern = string.match(l, "^\\mmzNewExtern")
					must_extract = must_extract or newExtern ~= nil
				end
				if must_extract then
					local extract_command = {
						args.options.memoize, -- Do not escape options.memoize to allow additional options
						pathutil.basename(pathutil.replaceext(file.abspath, "tex"))
					}
					coroutine.yield(table.concat(extract_command, " "))
					-- ensure document gets recompiled afterwards
					local succ, err = filesys.touch(file.path)
					if not succ then
						message.warn("Failed to touch " .. file.path .. " (" .. err .. ")")
					end
				end
			end
		end
	else
		-- Check log file
		if string.find(execlog, "Package memoize Warning") then
			message.diag("You may want to use --memoize option.")
		end
	end

	if args.options.sagetex then
		for _,file in ipairs(filelist) do
			-- usual compilation with sagetex
			-- tex      -> pdflatex tex -> aux,pdf,sage
			-- sage     -> sage sage    -> sout (eps)
			-- tex,sout -> pdflatex tex -> aux,pdf,sage
			local output_sout = pathutil.replaceext(file.abspath, "sout")
			if pathutil.ext(file.path) == "sage" then
				local sagefileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				if reruncheck.comparefileinfo({sagefileinfo}, args.auxstatus) then
					local sage_command = {
						args.options.sagetex, -- Do not escape options.sagetex to allow additional options
						pathutil.basename(file.abspath)
					}
					coroutine.yield(table.concat(sage_command, " "))
					-- watch for changes in .sage
					table.insert(filelist, {path = output_sout, abspath = output_sout, kind = "auxiliary"})
				else
					local succ, err = filesys.touch(output_sout)
					if not succ then
						message.warn("Failed to touch " .. output_sout .. " (" .. err .. ")")
					end
				end
			end
		end
	else
		-- Check log file
		if string.find(execlog, "Run Sage on") then
			message.diag("You may want to use --sagetex option.")
		end
	end

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
		local outfile = args.path_in_output_directory(args.output_extension)
		local oncopyerror:function():boolean
		if os.type == "windows" then
			oncopyerror = function(): boolean
				message.error("Failed to copy file.  Some applications may be locking the ", string.upper(args.options.output_format), " file.")
				return false
			end
		end
		coroutine.yield(fsutil.copy_command(outfile, args.options.output), oncopyerror)
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
