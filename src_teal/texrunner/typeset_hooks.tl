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

return {
	includeonly  = includeonly,
	memoize      = memoize,
	memoize_opts = memoize_opts,
	quiet        = quiet,

	ps_minted    = ps_minted,
	ps_epstopdf  = ps_epstopdf,

	check_driver = check_driver,

	makeindex   = makeindex,
	bibtex      = bibtex,
}
