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

local os      = require"os_"
local filesys = require "lfs"
local md5     = require "md5"

local option_t = require "texrunner.option_type"
local common_t = require "texrunner.common_types"
local engine_t = require "texrunner.tex_engine"

local message    = require "texrunner.message"
local pathutil   = require "texrunner.pathutil"
local shellutil  = require "texrunner.shellutil"
local reruncheck = require "texrunner.reruncheck"
local extract_bibtex_from_aux_file = require "texrunner.auxfile".extract_bibtex_from_aux_file

local checkdriver                  = require "texrunner.checkdriver".checkdriver

local function includeonly(options:option_t.Options, tex_options:engine_t.Option, tex_injection: string): string
	return string.format("%s\\includeonly{%s}", tex_injection or "", options.includeonly)
end

local function memoize(options:option_t.Options, tex_options:engine_t.Option, tex_injection: string): string
	return string.format("%s\\PassOptionsToPackage{no memo dir,extract=no}{memoize}", tex_injection or "")
end

local function memoize_opts(options:option_t.Options, tex_options:engine_t.Option, tex_injection: string): string
	return string.format("%s\\PassOptionsToPackage{%s}{memoize}", tex_injection or "", table.concat(options.memoize_opts, ","))
end

local function quiet(options:option_t.Options, tex_options:engine_t.Option, tex_injection: string): string
	if options.quiet >= 1 then
		tex_injection = string.format("%s\\AddToHook{begindocument/end}[quietX]{\\hbadness=99999 \\hfuzz=9999pt}", tex_injection or "")
	end
	if options.quiet >= 2 then
		tex_options.interaction = "batchmode"
		tex_injection = string.format("%s\\AddToHook{begindocument/end}[quiet]{\\nonstopmode}\\AddToHook{enddocument/info}[quiet]{\\batchmode}", tex_injection or "")
	end
	return tex_injection
end

local function ps_minted(options:option_t.Options, tex_options:engine_t.Option, tex_injection: string): string
	local outdir = options.output_directory
	if os.type == "windows" then
		outdir = string.gsub(outdir, "\\", "/") -- Use forward slashes
	end

	return string.format("%s\\PassOptionsToPackage{outputdir=%s}{minted}", tex_injection or "", outdir)
end

local function ps_epstopdf(options:option_t.Options, tex_options:engine_t.Option, tex_injection: string): string
	local outdir = options.output_directory
	if os.type == "windows" then
		outdir = string.gsub(outdir, "\\", "/") -- Use forward slashes
	end
	if string.sub(outdir, -1, -1) ~= "/" then
		outdir = outdir.."/" -- Must end with a directory separator
	end

	return string.format("%s\\PassOptionsToPackage{outdir=%s}{epstopdf}", tex_injection or "", outdir)
end

local function check_driver(options:option_t.Options, args:option_t.PostCompileArgs)
	checkdriver(options.check_driver, args.filelist)
end

-- needs to run in a coroutine => will yield commands that should be executed
local function makeindex(options:option_t.Options, args:option_t.PostCompileArgs)
	-- Look for .idx files and run MakeIndex
	for _,file in ipairs(args.filelist) do
		if pathutil.ext(file.path) == "idx" then
			-- Run makeindex if the .idx file is new or updated
			local idxfileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
			local output_ind = pathutil.replaceext(file.abspath, "ind")
			if reruncheck.comparefileinfo({idxfileinfo}, args.auxstatus) or reruncheck.comparefiletime(file.abspath, output_ind, args.auxstatus) then
				local idx_dir = pathutil.dirname(file.abspath)
				local makeindex_command = {
					"cd", shellutil.escape(idx_dir), "&&",
					options.makeindex, -- Do not escape options.makeindex to allow additional options
					"-o", pathutil.basename(output_ind),
					pathutil.basename(file.abspath)
				}
				coroutine.yield(table.concat(makeindex_command, " "))
				table.insert(args.filelist, {path = output_ind, abspath = output_ind, kind = "auxiliary"})
			else
				local succ, err = filesys.touch(output_ind)
				if not succ then
					message.warn("Failed to touch " .. output_ind .. " (" .. err .. ")")
				end
			end
		end
	end
end

local function glossaries(options:option_t.Options, args:option_t.PostCompileArgs)
	-- Look for configured files and run makeindex/xindy
	for _,file in ipairs(args.filelist) do
		for _, cfg in ipairs(options.glossaries) do
			if pathutil.ext(file.path) == cfg.inp then
				-- Run xindy/makeindex if the specified input-file is new or updated
				local inputfileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
				local outputfile = args.path_in_output_directory(cfg.out)
				if reruncheck.comparefileinfo({inputfileinfo}, args.auxstatus) or reruncheck.comparefiletime(file.abspath, outputfile, args.auxstatus) then
					coroutine.yield(cfg.cmd(args.path_in_output_directory))
					table.insert(args.filelist, {path = outputfile, abspath = outputfile, kind = "auxiliary"})
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

local function bibtex(options:option_t.Options, args:option_t.PostCompileArgs)
	local mainauxfile = args.path_in_output_directory("aux")
	local biblines2 = extract_bibtex_from_aux_file(mainauxfile, options.output_directory)
	local bibtex_aux_hash2: string
	if #biblines2 > 0 then
		bibtex_aux_hash2 = md5.sum(table.concat(biblines2, "\n"))
	end
	local output_bbl = args.path_in_output_directory("bbl")
	if args.bibtex_aux_hash ~= bibtex_aux_hash2 or reruncheck.comparefiletime(pathutil.abspath(mainauxfile), output_bbl, args.auxstatus) then
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
end

local function biber(options:option_t.Options, args:option_t.PostCompileArgs)
	local mainauxfile = args.path_in_output_directory("aux")
	for _,file in ipairs(args.filelist) do
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
					options.biber, -- Do not escape options.biber to allow additional options
					"--output-directory", shellutil.escape(options.output_directory),
					pathutil.basename(file.abspath)
				}
				coroutine.yield(table.concat(biber_command, " "))
				-- watch for changes in the bbl
				table.insert(args.filelist, {path = output_bbl, abspath = output_bbl, kind = "auxiliary"})
			else
				local succ, err = filesys.touch(output_bbl)
				if not succ then
					message.warn("Failed to touch " .. output_bbl .. " (" .. err .. ")")
				end
			end
		end
	end
end

local function memoize_run(options:option_t.Options, args:option_t.PostCompileArgs)
	for _,file in ipairs(args.filelist) do
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
end

local function sagetex(options:option_t.Options, args:option_t.PostCompileArgs)
	for _,file in ipairs(args.filelist) do
		-- usual compilation with sagetex
		-- tex      -> pdflatex tex -> aux,pdf,sage
		-- sage     -> sage sage    -> sout (eps)
		-- tex,sout -> pdflatex tex -> aux,pdf,sage
		local output_sout = pathutil.replaceext(file.abspath, "sout")
		if pathutil.ext(file.path) == "sage" then
			local sagefileinfo = {path = file.path, abspath = file.abspath, kind = "auxiliary"}
			if reruncheck.comparefileinfo({sagefileinfo}, args.auxstatus) then
				local sage_command = {
					options.sagetex, -- Do not escape options.sagetex to allow additional options
					pathutil.basename(file.abspath)
				}
				coroutine.yield(table.concat(sage_command, " "))
				-- watch for changes in .sage
				table.insert(args.filelist, {path = output_sout, abspath = output_sout, kind = "auxiliary"})
			else
				local succ, err = filesys.touch(output_sout)
				if not succ then
					message.warn("Failed to touch " .. output_sout .. " (" .. err .. ")")
				end
			end
		end
	end
end

-- generic hook function to get a sorted list of priorities
local function sort_prios(hook_table: {number: {function, string}}): {number}
	local priorities = {}
	for prio in pairs(hook_table) do
		table.insert(priorities, prio)
	end
	table.sort(priorities)
	return priorities
end

-- generic hook function to check if a hook-tuple is valid
local function validate(hook: {function, string, boolean}): boolean, string
	if not hook or not hook[1] or not hook[2] then
		return false, "Malformed hook"
	end
	return true, nil
end

-- returns the new tex_injection string
local function apply_tex_injection(hooks: {number: {option_t.Hooks.tex_injection_func, string}}, options: option_t.Options, tex_options: engine_t.Option, tex_injection:string): string
	local sorted_prios = sort_prios(hooks as {number: {function, string}})
	local result = tex_injection
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = validate(hook)
		if not valid then
			error("Invalid hook: " .. err)
		end
		 if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("Executing tex_injection hook '", hook[2], "'")
		end
		result = hook[1](options, tex_options, result)
	end
	return result
end

-- only does message.diag, no modifications, no return
local function apply_suggestion_file_based(hooks: {number: {option_t.Hooks.suggestion_file_based_func, string, boolean}}, filelist:{common_t.Filemap_ele})
	local sorted_prios = sort_prios(hooks as {number: {function, string}})
	-- check if all hooks are valid
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = validate(hook)
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

-- only does message.diag, no modifications, no return
local function apply_suggestion_excelog_based(hooks: {number: {option_t.Hooks.suggestion_execlog_based_func, string}}, execlog: string, o:option_t.Options)
	local sorted_prios = sort_prios(hooks as {number: {function, string}})
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = validate(hook)
		if not valid then
			error("Invalid hook: " .. err)
		end
		if hook[1](execlog, o) then
			message.diag(hook[2])
		end
	end
end

-- must run in the coroutine
-- yields shell commands to be executed
local function apply_post_compile(hooks: {number: {option_t.Hooks.post_compile_func, string}}, options: option_t.Options, args: option_t.PostCompileArgs)
	local sorted_prios = sort_prios(hooks as {number: {function, string}})
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = validate(hook)
		if not valid then
			error("Invalid hook: " .. err)
		end
		 if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("Executing post_compile hook '", hook[2], "'")
		end
		hook[1](options, args)
	end
end

-- must run in the coroutine
-- yields shell commands to be executed
local function apply_post_build(hooks: {number: {option_t.Hooks.post_build_func, string}}, options: option_t.Options)
	local sorted_prios = sort_prios(hooks as {number: {function, string}})
	for _, prio in ipairs(sorted_prios) do
		local hook = hooks[prio]
		local valid, err = validate(hook)
		if not valid then
			error("Invalid hook: " .. err)
		end
		 if CLUTTEALTEX_VERBOSITY >= 1 then
			message.info("Executing post_build hook '", hook[2], "'")
		end
		hook[1](options)
	end
end

return {
	-- tex_injection hooks
	includeonly  = includeonly,
	memoize      = memoize,
	memoize_opts = memoize_opts,
	quiet        = quiet,

	-- suggestion_file_based hooks
	ps_minted    = ps_minted,
	ps_epstopdf  = ps_epstopdf,

	-- hook
	check_driver = check_driver,

	-- post_compile hooks
	makeindex   = makeindex,
	glossaries  = glossaries,
	bibtex      = bibtex,
	biber       = biber,
	memoize_run = memoize_run,
	sagetex     = sagetex,

	-- functions for hook management
	apply_post_compile             = apply_post_compile,
	apply_tex_injection            = apply_tex_injection,
	apply_suggestion_file_based    = apply_suggestion_file_based,
	apply_suggestion_excelog_based = apply_suggestion_excelog_based,
	apply_post_build               = apply_post_build,

	-- internal
	sort_prios = sort_prios,
	validate   = validate,
}
