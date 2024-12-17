#!/usr/bin/env texlua
--[[
  Copyright 2016-2021 ARATA Mizuki
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

global CLUTTEALTEX_VERSION: string = "v0.8.0"

-- Standard libraries
local table = table
local os = require"os_"
local io = io
local string = string
local ipairs = ipairs
local coroutine = coroutine
local tostring = tostring

-- External libraries (included in texlua)
local filesys = require "lfs"
local md5     = require "md5"
-- local kpse = require "kpse"

-- My own modules
local pathutil    = require "texrunner.pathutil"
local fsutil      = require "texrunner.fsutil"
local shellutil   = require "texrunner.shellutil"
local reruncheck  = require "texrunner.reruncheck"
local luatexinit  = require "texrunner.luatexinit"
local recoverylib = require "texrunner.recovery"
local message     = require "texrunner.message"
local safename    = require "texrunner.safename"
local extract_bibtex_from_aux_file = require "texrunner.auxfile".extract_bibtex_from_aux_file
local handle_cluttealtex_options = require "texrunner.handleoption".handle_cluttealtex_options
local checkdriver = require "texrunner.checkdriver".checkdriver
local engine_t = require "texrunner.tex_engine"
local fswatcherlib_t = require"texrunner.fswatcher"

os.setlocale("", "ctype") -- Workaround for recent Universal CRT

-- arguments: input file name, jobname, etc...
local function genOutputDirectory(...: string): string
	-- The name of the temporary directory is based on the path of input file.
	local message = table.concat({...}, "\0")
	local hash = md5.sumhexa(message)
	local tmpdir = os.getenv("TMPDIR") or os.getenv("TMP") or os.getenv("TEMP")
	if tmpdir == nil then
		local home = os.getenv("HOME") or os.getenv("USERPROFILE") or error("environment variable 'TMPDIR' not set!")
		tmpdir = pathutil.join(home, ".latex-build-temp")
	end
	return pathutil.join(tmpdir, 'latex-build-' .. hash)
end

local inputfile, engine, options = handle_cluttealtex_options(arg)

local jobname_for_output: string
if options.jobname == nil then
	local basename = pathutil.basename(pathutil.trimext(inputfile))
	options.jobname = safename.escapejobname(basename)
	jobname_for_output = basename
else
	jobname_for_output = options.jobname
end
local jobname = options.jobname
assert(jobname ~= "", "jobname cannot be empty")

local output_extension: string
if options.output_format == "dvi" then
	output_extension = engine.dvi_extension or "dvi"
else
	output_extension = "pdf"
end

if options.output == nil then
	options.output = jobname_for_output .. "." .. output_extension
end

-- Prepare output directory
if options.output_directory == nil then
	local inputfile_abs = pathutil.abspath(inputfile)
	options.output_directory = genOutputDirectory(inputfile_abs, jobname, options.engine_executable or options.engine)

	if not fsutil.isdir(options.output_directory) then
		assert(fsutil.mkdir_rec(options.output_directory))

	elseif options.fresh then
		-- The output directory exists and --fresh is given:
		-- Remove all files in the output directory
		if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("Cleaning '", options.output_directory, "'...")
		end
		assert(fsutil.remove_rec(options.output_directory))
		assert(filesys.mkdir(options.output_directory))
	end

elseif options.fresh then
	message.error("--fresh and --output-directory cannot be used together.")
	os.exit(1)
end

-- --print-output-directory
if options.print_output_directory then
	io.write(options.output_directory, "\n")
	os.exit(0)
end

local pathsep = ":"
if os.type == "windows" then
	pathsep = ";"
end

local original_wd = filesys.currentdir()
if options.change_directory then
	local TEXINPUTS = os.getenv("TEXINPUTS") or ""
	local LUAINPUTS = os.getenv("LUAINPUTS") or ""
	assert(filesys.chdir(options.output_directory))
	options.output = pathutil.abspath(options.output, original_wd)
	os.setenv("TEXINPUTS", original_wd .. pathsep .. TEXINPUTS)
	os.setenv("LUAINPUTS", original_wd .. pathsep .. LUAINPUTS)
	-- after changing the pwd, '.' is always the output_directory (needed for some path generation)
	options.output_directory = "."
end
if options.bibtex or options.biber then
	local BIBINPUTS = os.getenv("BIBINPUTS") or ""
	options.output = pathutil.abspath(options.output, original_wd)
	os.setenv("BIBINPUTS", original_wd .. pathsep .. BIBINPUTS)
end

-- Set `max_print_line' environment variable if not already set.
if os.getenv("max_print_line") == nil then
	if options.bibtex then
		os.setenv("max_print_line", "19999")
	else
		os.setenv("max_print_line", "65536")
	end
end
-- TODO: error_line, half_error_line
--[[
  According to texmf.cnf:
	45 < error_line < 255,
	30 < half_error_line < error_line - 15,
	60 <= max_print_line.
]]

local function path_in_output_directory(ext:string): string
	return pathutil.join(options.output_directory, jobname .. "." .. ext)
end

local recorderfile = path_in_output_directory("fls")
local recorderfile2 = path_in_output_directory("cluttealtex-fls")

local tex_options:engine_t.Option = {
	engine_executable = options.engine_executable,
	interaction = options.interaction,
	file_line_error = options.file_line_error,
	halt_on_error = options.halt_on_error,
	synctex = options.synctex,
	output_directory = options.output_directory,
	shell_escape = options.shell_escape,
	shell_restricted = options.shell_restricted,
	jobname = options.jobname,
	fmt = options.fmt,
	extraoptions = options.tex_extraoptions,
}
if options.output_format ~= "pdf" and engine.supports_pdf_generation then
	tex_options.output_format = options.output_format
end

-- Setup LuaTeX initialization script
if engine.is_luatex then
	local initscriptfile = path_in_output_directory("cluttealtexinit.lua")
	luatexinit.create_initialization_script(initscriptfile, tex_options)
	tex_options.lua_initialization_script = initscriptfile
end

-- handle change_directory properly (needs to be after initscript gen)
if options.change_directory then
	tex_options.output_directory = nil
end

-- Run TeX command (*tex, *latex)
-- should_rerun, newauxstatus = single_run([auxstatus])
-- This function should be run in a coroutine.
local function single_run(auxstatus:{string:reruncheck.Status}, iteration:integer): boolean|string, {string:reruncheck.Status}
	local minted, epstopdf = false, false
	local bibtex_aux_hash:string = nil
	local mainauxfile = path_in_output_directory("aux")
	if fsutil.isfile(recorderfile) then
		-- Recorder file already exists
		local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
		if engine.is_luatex and fsutil.isfile(recorderfile2) then
			filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
		end
		auxstatus = reruncheck.collectfileinfo(filelist, auxstatus)
		for _,fileinfo in ipairs(filelist) do
			if string.match(fileinfo.path, "minted/minted%.sty$") then
				minted = true
			end
			if string.match(fileinfo.path, "epstopdf%.sty$") then
				epstopdf = true
			end
		end
		if options.bibtex then
			local biblines = extract_bibtex_from_aux_file(mainauxfile, options.output_directory)
			if #biblines > 0 then
				bibtex_aux_hash = md5.sum(table.concat(biblines, "\n"))
			end
		end
		if iteration == 1 and not options.watch then
			local outfile = path_in_output_directory(output_extension)
			if not reruncheck.anyNonOutputNewerThan(filelist, outfile) then
				return false, auxstatus
			end
		end
	else
		-- This is the first execution
		if auxstatus ~= nil then
			message.error("Recorder file was not generated during the execution!")
			os.exit(1)
		end
		auxstatus = {}
	end
	--local timestamp = os.time()

	local tex_injection = ""

	if options.includeonly then
		tex_injection = string.format("%s\\includeonly{%s}", tex_options.tex_injection or "", options.includeonly)
	end

	if minted or options.package_support["minted"] then
		local outdir = options.output_directory
		if os.type == "windows" then
			outdir = string.gsub(outdir, "\\", "/") -- Use forward slashes
		end
		tex_injection = string.format("%s\\PassOptionsToPackage{outputdir=%s}{minted}", tex_injection or "", outdir)
		if not options.package_support["minted"] then
			message.diag("You may want to use --package-support=minted option.")
		end
	end
	if epstopdf or options.package_support["epstopdf"] then
		local outdir = options.output_directory
		if os.type == "windows" then
			outdir = string.gsub(outdir, "\\", "/") -- Use forward slashes
		end
		if string.sub(outdir, -1, -1) ~= "/" then
			outdir = outdir.."/" -- Must end with a directory separator
		end
		tex_injection = string.format("%s\\PassOptionsToPackage{outdir=%s}{epstopdf}", tex_injection or "", outdir)
		if not options.package_support["epstopdf"] then
			message.diag("You may want to use --package-support=epstopdf option.")
		end
	end
	if options.memoize then
		tex_injection = string.format("%s\\PassOptionsToPackage{no memo dir,extract=no}{memoize}", tex_injection or "")
	end
	if options.memoize_opts then
		tex_injection = string.format("%s\\PassOptionsToPackage{%s}{memoize}", tex_injection or "", table.concat(options.memoize_opts, ","))
	end
	if options.quiet then
		if options.quiet >= 1 then
			tex_injection = string.format("%s\\AddToHook{begindocument/end}[quietX]{\\hbadness=99999 \\hfuzz=9999pt}", tex_injection or "")
		end
		if options.quiet >= 2 then
			tex_options.interaction = "batchmode"
			tex_injection = string.format("%s\\AddToHook{begindocument/end}[quiet]{\\nonstopmode}\\AddToHook{enddocument/info}[quiet]{\\batchmode}", tex_injection or "")
		end
	end

	local inputline = tex_injection .. safename.safeinput(inputfile, engine)

	local current_tex_options, lightweight_mode = tex_options, false
	if iteration == 1 and options.start_with_draft then
		current_tex_options = {}
		for k,v in pairs(tex_options as {string:any}) do
			(current_tex_options as {string:any})[k] = v
		end
		if engine.supports_draftmode then
			current_tex_options.draftmode = true
			options.start_with_draft = false
		end
		current_tex_options.interaction = "batchmode"
		lightweight_mode = true
	else
		current_tex_options.draftmode = false
	end

	local command = engine:build_command(inputline, current_tex_options)

	local execlog:string -- the contents of .log file

	local recovered = false
	local function recover(): boolean
		-- Check log file
		if not execlog then
			local logfile = assert(io.open(path_in_output_directory("log")))
			execlog = logfile:read("*a")
			logfile:close()
		end
		recovered = recoverylib.try_recovery{
			execlog = execlog,
			auxfile = path_in_output_directory("aux"),
			options = options,
			original_wd = original_wd,
		}
		return recovered
	end
	coroutine.yield(command, recover) -- Execute the command
	if recovered then
		return true, {}
	end

	local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
	if engine.is_luatex and fsutil.isfile(recorderfile2) then
		filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
	end

	if not execlog then
		local logfile = assert(io.open(path_in_output_directory("log")))
		execlog = logfile:read("*a")
		logfile:close()
	end

	if options.check_driver ~= nil then
		checkdriver(options.check_driver, filelist)
	end

	if options.makeindex then
		-- Look for .idx files and run MakeIndex
		for _,file in ipairs(filelist) do
			if pathutil.ext(file.path) == "idx" then
				-- Run makeindex if the .idx file is new or updated
				local idxfileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				local output_ind = pathutil.replaceext(file.abspath, "ind")
				if reruncheck.comparefileinfo({idxfileinfo}, auxstatus) or reruncheck.comparefiletime(file.abspath, output_ind, auxstatus) then
					local idx_dir = pathutil.dirname(file.abspath)
					local makeindex_command = {
						"cd", shellutil.escape(idx_dir), "&&",
						options.makeindex, -- Do not escape options.makeindex to allow additional options
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

	if options.glossaries then
		-- Look for configured files and run makeindex/xindy
		for _,file in ipairs(filelist) do
			for _, cfg in ipairs(options.glossaries) do
				if pathutil.ext(file.path) == cfg.inp then
					-- Run xindy/makeindex if the specified input-file is new or updated
					local inputfileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
					local outputfile = path_in_output_directory(cfg.out)
					if reruncheck.comparefileinfo({inputfileinfo}, auxstatus) or reruncheck.comparefiletime(file.abspath, outputfile, auxstatus) then
						print(cfg.cmd(path_in_output_directory))
						coroutine.yield(cfg.cmd(path_in_output_directory))
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

	if options.bibtex then
		local biblines2 = extract_bibtex_from_aux_file(mainauxfile, options.output_directory)
		local bibtex_aux_hash2: string
		if #biblines2 > 0 then
			bibtex_aux_hash2 = md5.sum(table.concat(biblines2, "\n"))
		end
		local output_bbl = path_in_output_directory("bbl")
		if bibtex_aux_hash ~= bibtex_aux_hash2 or reruncheck.comparefiletime(pathutil.abspath(mainauxfile), output_bbl, auxstatus) then
			-- The input for BibTeX command has changed...
			-- os.execute("pwd")
			-- os.execute("echo $BIBINPUTS")
			local bibtex_command = {
				"cd", shellutil.escape(options.output_directory), "&&",
				options.bibtex,
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
	elseif options.biber then
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
						local bibfile = pathutil.join(original_wd, bib)
						local succ, err = io.open(bibfile, "r") -- check if file is present, don't use touch to avoid triggering a rerun
						if succ then
							succ:close()
							local updated_dot_bib_tmp = not reruncheck.comparefiletime(pathutil.abspath(mainauxfile), bibfile, auxstatus)
							if updated_dot_bib_tmp then
								message.info(bibfile.." is newer than aux")
							end
							updated_dot_bib = updated_dot_bib_tmp or updated_dot_bib
						else
							message.warn(bibfile .. " is not accessible (" .. err .. ")")
						end
					end
				end
				if updated_dot_bib or reruncheck.comparefileinfo({bcffileinfo}, auxstatus) or reruncheck.comparefiletime(file.abspath, output_bbl, auxstatus) then
					local biber_command = {
						options.biber, -- Do not escape options.biber to allow additional options
						"--output-directory", shellutil.escape(options.output_directory),
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

	if options.memoize then
		for _,file in ipairs(filelist) do
			-- usual compilation with memoize
			-- tex      -> pdflatex tex    -> aux,pdf,mmz
			-- mmz,pdf  -> memoize-extract -> pdf,pdf
			-- tex      -> pdflatex tex    -> aux,pdf
			if pathutil.ext(file.path) == "mmz" then
				local memoizefileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				local must_extract = false
				for l in io.lines(file.abspath) do
					local newExtern = string.match(l, "^\\mmzNewExtern")
					must_extract = must_extract or newExtern ~= nil
				end
				if must_extract then
					local extract_command = {
						options.memoize, -- Do not escape options.memoize to allow additional options
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

	if options.sagetex then
		for _,file in ipairs(filelist) do
			-- usual compilation with sagetex
			-- tex      -> pdflatex tex -> aux,pdf,sage
			-- sage     -> sage sage    -> sout (eps)
			-- tex,sout -> pdflatex tex -> aux,pdf,sage
			local output_sout = pathutil.replaceext(file.abspath, "sout")
			if pathutil.ext(file.path) == "sage" then
				local sagefileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				if reruncheck.comparefileinfo({sagefileinfo}, auxstatus) then
					local sage_command = {
						options.sagetex, -- Do not escape options.sagetex to allow additional options
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

	local should_rerun, auxstatus = reruncheck.comparefileinfo(filelist, auxstatus)
	return should_rerun or lightweight_mode, auxstatus
end

-- Run (La)TeX (possibly multiple times) and produce a PDF file.
-- This function should be run in a coroutine.
local function do_typeset_c(): string, function
	local iteration = 0
	local should_rerun, auxstatus: boolean|string, {string:reruncheck.Status}
	repeat
		iteration = iteration + 1
		should_rerun, auxstatus = single_run(auxstatus, iteration)
		if should_rerun == "No pages of output." then
			message.warn("No pages of output.")
			return
		end
	until not should_rerun or iteration >= options.max_iterations

	if should_rerun then
		message.warn("LaTeX should be run once more.")
	end

	-- Successful
	if options.output_format == "dvi" or engine.supports_pdf_generation then
		-- Output file (DVI/PDF) is generated in the output directory
		local outfile = path_in_output_directory(output_extension)
		local oncopyerror:function():boolean
		if os.type == "windows" then
			oncopyerror = function(): boolean
				message.error("Failed to copy file.  Some applications may be locking the ", string.upper(options.output_format), " file.")
				return false
			end
		end
		coroutine.yield(fsutil.copy_command(outfile, options.output), oncopyerror)
		if #options.dvipdfmx_extraoptions > 0 then
			message.warn("--dvipdfmx-option[s] are ignored.")
		end

	else
		-- DVI file is generated, but PDF file is wanted
		local dvifile = path_in_output_directory("dvi")
		local dvipdfmx_command = {"dvipdfmx", "-o", shellutil.escape(options.output)}
		for _,v in ipairs(options.dvipdfmx_extraoptions) do
			table.insert(dvipdfmx_command, v)
		end
		table.insert(dvipdfmx_command, shellutil.escape(dvifile))
		coroutine.yield(table.concat(dvipdfmx_command, " "))
	end

	-- Copy SyncTeX file if necessary
	if options.output_format == "pdf" then
		local synctex = tonumber(options.synctex or "0")
		local synctex_ext:string = nil
		if synctex > 0 then
			-- Compressed SyncTeX file (.synctex.gz)
			synctex_ext = "synctex.gz"
		elseif synctex < 0 then
			-- Uncompressed SyncTeX file (.synctex)
			synctex_ext = "synctex"
		end
		if synctex_ext then
			coroutine.yield(fsutil.copy_command(path_in_output_directory(synctex_ext), pathutil.replaceext(options.output, synctex_ext)))
		end
	end

	-- Write dependencies file
	if options.make_depends then
		local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
		if engine.is_luatex and fsutil.isfile(recorderfile2) then
			filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
		end
		local f = assert(io.open(options.make_depends, "w"))
		f:write(options.output, ":")
		for _,fileinfo in ipairs(filelist) do
			if fileinfo.kind == "input" then
				f:write(" ", fileinfo.path)
			end
		end
		f:write("\n")
		f:close()
	end
end

local function do_typeset(): boolean, string, integer
	-- Execute the command string yielded by do_typeset_c
	for command, recover in coroutine.wrap(do_typeset_c) do
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

if options.watch then
	-- Watch mode

	local fswatcherlib:fswatcherlib_t.WatcherMod = nil
	if os.type == "windows" then
		-- Windows: Try built-in filesystem watcher
		local succ, result = pcall(require, "texrunner.fswatcher_windows")
		if not succ and CLUTTEALTEX_VERBOSITY >= 1 then
			message.warn("Failed to load texrunner.fswatcher_windows: " .. result as string)
		end
		fswatcherlib = result
	end

	local do_watch: function({string}):boolean
	local max_watches: integer
	if fswatcherlib then
		max_watches = -1 -- no limit known to me
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using built-in filesystem watcher for Windows")
		end
		do_watch = function(files:{string}): boolean
			local watcher = assert(fswatcherlib.new())
			for _,path in ipairs(files) do
				assert(watcher:add_file(path))
			end
			local result = assert(watcher:next())
			if CLUTTEALTEX_VERBOSITY >= 2 then
				message.info(string.format("%s %s", result.action, result.path))
			end
			watcher:close()
			return true
		end
	elseif (options.watch == "auto" or options.watch == "fswatch") and shellutil.has_command("fswatch") then
		max_watches = -1 -- no limit known to me
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using `fswatch' command")
		end
		do_watch = function(files:{string}): boolean
			local fswatch_command = {"fswatch", "--one-event", "--event=Updated", "--"}
			for _,path in ipairs(files) do
				table.insert(fswatch_command, shellutil.escape(path))
			end
			local fswatch_command_str = table.concat(fswatch_command, " ")
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.exec(fswatch_command_str)
			end
			local fswatch = assert(io.popen(fswatch_command_str, "r"))
			for l in fswatch:lines() do
				for _,path in ipairs(files) do
					if l == path then
						fswatch:close()
						return true
					end
				end
			end
			return false
		end
	elseif (options.watch == "auto" or options.watch == "inotifywait") and shellutil.has_command("inotifywait") then
		max_watches = 1024 -- see https://github.com/inotify-tools/inotify-tools/blob/210b019fb621d32fd6986b512508fc845f6c9fcb/src/common.cpp#L18C20-L18C24
		if CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("Using `inotifywait' command")
		end
		do_watch = function(files:{string}): boolean
			local inotifywait_command = {"inotifywait", "--event=modify", "--event=attrib", "--format=%w", "--quiet"}
			for _,path in ipairs(files) do
				table.insert(inotifywait_command, shellutil.escape(path))
			end
			local inotifywait_command_str = table.concat(inotifywait_command, " ")
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.exec(inotifywait_command_str)
			end
			local inotifywait = assert(io.popen(inotifywait_command_str, "r"))
			for l in inotifywait:lines() do
				for _,path in ipairs(files) do
					if l == path then
						inotifywait:close()
						return true
					end
				end
			end
			return false
		end
	else
		if options.watch == "auto" then
			message.error("Could not watch files because neither `fswatch' nor `inotifywait' was installed.")
		elseif options.watch == "fswatch" then
			message.error("Could not watch files because your selected engine `fswatch' was not installed.")
		elseif options.watch == "inotifywait" then
			message.error("Could not watch files because your selected engine `inotifywait' was not installed.")
		end
		message.info("See CluttealTeX's manual for details.")
		os.exit(1)
	end

	local _, _ = do_typeset()
	-- TODO: filenames here can be UTF-8 if command_line_encoding=utf-8
	local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
	if engine.is_luatex and fsutil.isfile(recorderfile2) then
		filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
	end

	local function gather_input_files_to_watch(filelist: {reruncheck.Filemap_ele}): {string}
		local input_files_to_watch = {}
		for _,fileinfo in ipairs(filelist) do
			if fileinfo.kind == "input" then
				local watch = false
				if options.watch_inc_exc then
					watch = false
					for _,v in ipairs(options.watch_inc_exc) do
						if v.type == "only_path" then
							if string.sub(fileinfo.abspath, 1, #v.param) == v.param then
								watch = true
							end
						elseif v.type == "only_ext" then
							if pathutil.ext(fileinfo.abspath) == v.param then
								watch = true
							end
						elseif v.type == "not_path" then
							if string.sub(fileinfo.abspath, 1, #v.param) == v.param then
								watch = false
							end
						elseif v.type == "not_ext" then
							if pathutil.ext(fileinfo.abspath) == v.param then
								watch = false
							end
						end
					end
				else
					watch = true
				end

				if watch then
					table.insert(input_files_to_watch, fileinfo.abspath)
				end
			end
		end
		if max_watches >= 0 and #input_files_to_watch > max_watches then
			message.warn(string.format(
			"Collected %d input files to watch on. Typically only %d hooks are created." ..
			"The hooks exceeding this limit typically will simply not being installed." ..
			"Consider either to increase this limit (how/if possible depends on the watcher engine) or" ..
			"make use of the --watch-{only,no}-{ext,path} options to restrict the files which CluttealTeX should watch.",
				#input_files_to_watch, max_watches
			))
		end
		return input_files_to_watch
	end

	local input_files_to_watch = gather_input_files_to_watch(filelist)
	while do_watch(input_files_to_watch) do
		local success, _ = do_typeset()
		if not success then
			-- error
		else
			local filelist, filemap = reruncheck.parse_recorder_file(recorderfile, options)
			if engine.is_luatex and fsutil.isfile(recorderfile2) then
				filelist, filemap = reruncheck.parse_recorder_file(recorderfile2, options, filelist, filemap)
			end
			input_files_to_watch = gather_input_files_to_watch(filelist)
		end
	end

else
	-- Not in watch mode
	local success, _ = do_typeset()
	if not success then
		os.exit(1)
	end
end
