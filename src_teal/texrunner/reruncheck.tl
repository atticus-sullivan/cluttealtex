--[[
Copyright 2016,2018 ARATA Mizuki
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

local io = io
local assert = assert
local filesys = require "lfs"
local md5 = require "md5"
local fsutil = require "texrunner.fsutil"
local pathutil = require "texrunner.pathutil"
local message = require "texrunner.message"
local options = require"texrunner.option_type"

local function md5sum_file(path:string): string
	local f = assert(io.open(path, "rb"))
	local contents = f:read("*a")
	f:close()
	return md5.sum(contents)
end

local record Module
	record Filemap_ele
		path: string
		abspath: string
		kind: string -- enum
	end
	record Status
		mtime: number
		size: number
		md5sum: string
	end

	parse_recorder_file: function(string, options.Options, ?{Module.Filemap_ele}, ?{string:Module.Filemap_ele}): {Module.Filemap_ele}, {string:Module.Filemap_ele}
	collectfileinfo: function({Module.Filemap_ele}, {string:Module.Status}): {string:Module.Status}
	comparefileinfo: function({Module.Filemap_ele}, {string:Module.Status}): boolean, {string:Module.Status}
	comparefiletime: function(string, string, {string:Module.Status}): boolean
	anyNonOutputNewerThan: function(filelist:{Module.Filemap_ele}, reference: string): boolean
end

-- filelist, filemap = parse_recorder_file("jobname.fls", options [, filelist, filemap])
-- filelist[i] = {path = "...", abspath = "...", kind = "input" or "output" or "auxiliary"}
local function parse_recorder_file(file:string, options:options.Options, filelist?:{Module.Filemap_ele}, filemap?:{string:Module.Filemap_ele}): {Module.Filemap_ele}, {string:Module.Filemap_ele}
filelist = filelist or {}
	filemap = filemap or {}
	for l in io.lines(file) do
		local t,path = l:match("^(%w+) (.*)$")
		if t == "PWD" then
			-- Ignore
		elseif t == "INPUT" then
			local abspath = pathutil.abspath(path)
			local fileinfo = filemap[abspath]
			if not fileinfo then
				if fsutil.isfile(path) then
					local kind = "input"
					local ext = pathutil.ext(path)
					if ext == "bbl" then
						kind = "auxiliary"
					end
					if options.glossaries then
						for _,i in ipairs(options.glossaries) do
							if pathutil.ext(abspath) == i.out then
								kind = "auxiliary"
							end
						end
					end
					fileinfo = {path = path, abspath = abspath, kind = kind}
					table.insert(filelist, fileinfo)
					filemap[abspath] = fileinfo
				else
					-- Maybe a command execution
				end
			else
				if #path < #fileinfo.path then
					fileinfo.path = path
				end
				if fileinfo.kind == "output" then
					-- The files listed in both INPUT and OUTPUT are considered to be auxiliary files.
					fileinfo.kind = "auxiliary"
				end
			end
		elseif t == "OUTPUT" then
			local abspath = pathutil.abspath(path)
			local fileinfo = filemap[abspath]
			if not fileinfo then
				local kind = "output"
				local ext = pathutil.ext(path)
				if ext == "out" then
					-- hyperref bookmarks file
					kind = "auxiliary"
				elseif options.makeindex and ext == "idx" then
					-- Treat .idx files (to be processed by MakeIndex) as auxiliary
					kind = "auxiliary"
					-- ...and .ind files
				elseif ext == "bcf" then -- biber
					kind = "auxiliary"
				elseif ext == "sage" then -- sagetex
					kind = "auxiliary"
				elseif ext == "mmz" or ext == "memo" then -- memoize
					kind = "auxiliary"
				-- check for glossaries must be at the end if using elseif all the way down
				elseif options.glossaries then
					for _,i in ipairs(options.glossaries) do
						if pathutil.ext(abspath) == i.inp then
							kind = "auxiliary"
						end
					end
				end
				fileinfo = {path = path, abspath = abspath, kind = kind}
				table.insert(filelist, fileinfo)
				filemap[abspath] = fileinfo
			else
				if #path < #fileinfo.path then
					fileinfo.path = path
				end
				if fileinfo.kind == "input" then
					-- The files listed in both INPUT and OUTPUT are considered to be auxiliary files.
					fileinfo.kind = "auxiliary"
				end
			end
		else
			message.warn("Unrecognized line in recorder file '", file, "': ", l)
		end
	end
	return filelist, filemap
end

-- auxstatus = collectfileinfo(filelist [, auxstatus])
local function collectfileinfo(filelist:{Module.Filemap_ele}, auxstatus:{string:Module.Status}): {string:Module.Status}
	auxstatus = auxstatus or {}
	for _,fileinfo in ipairs(filelist) do
		local path = fileinfo.abspath
		if fsutil.isfile(path) then
			local status = auxstatus[path] or {}
			auxstatus[path] = status
			if fileinfo.kind == "input" then
				if not status.mtime then
					local mtime = filesys.attributes(path, "modification")
					if mtime is number then
						status.mtime = mtime
					else
						error(("query lfs for 'modification' returned type %s"):format(type(mtime)))
					end
				end
			elseif fileinfo.kind == "auxiliary" then
				if not status.mtime then
					local mtime = filesys.attributes(path, "modification")
					if mtime is number then
						status.mtime = mtime
					else
						error(("query lfs for 'modification' returned type %s"):format(type(mtime)))
					end
				end
				if not status.size then
					local size = filesys.attributes(path, "size")
					if size is number then
						status.size = size
					else
						error(("query lfs for 'size' returned type %s"):format(type(size)))
					end
				end
				status.md5sum = status.md5sum or md5sum_file(path)
			end
		end
	end
	return auxstatus
end

local function binarytohex(s:string): string
	local r = s:gsub(".", function(c:string): string
		local r = string.format("%02x", string.byte(c))
		return r
	end)
	return r
end

-- should_rerun, newauxstatus = comparefileinfo(auxfiles, auxstatus)
local function comparefileinfo(filelist:{Module.Filemap_ele}, auxstatus:{string:Module.Status}): boolean, {string:Module.Status}
local should_rerun = false
	local newauxstatus:{string:Module.Status} = {}
	for _,fileinfo in ipairs(filelist) do
		local path = fileinfo.abspath
		if fsutil.isfile(path) then
			if fileinfo.kind == "input" then
				-- Input file: User might have modified while running TeX.
				local mtime = filesys.attributes(path, "modification")
				if mtime is number then
					if auxstatus[path] and auxstatus[path].mtime then
						if auxstatus[path].mtime < mtime then
							-- Input file was updated during execution
							message.info("Input file '", fileinfo.path, "' was modified (by user, or some external commands).")
							newauxstatus[path] = {mtime = mtime}
							return true, newauxstatus
						end
						else
						-- New input file
					end
				else
					error(("query lfs for 'modification' returned type %s"):format(type(mtime)))
				end

			elseif fileinfo.kind == "auxiliary" then
				-- Auxiliary file: Compare file contents.
				if auxstatus[path] then
					-- File was touched during execution
					local really_modified = false
					local modified_because:string = nil
					local size = filesys.attributes(path, "size")
					if size is number then
						if auxstatus[path].size ~= size then
							really_modified = true
							if auxstatus[path].size then
								modified_because = string.format("size: %d -> %d", auxstatus[path].size, size)
							else
								modified_because = string.format("size: (N/A) -> %d", size)
							end
							newauxstatus[path] = {size = size}
						else
							local md5sum = md5sum_file(path)
							if auxstatus[path].md5sum ~= md5sum then
								really_modified = true
								if auxstatus[path].md5sum then
									modified_because = string.format("md5: %s -> %s", binarytohex(auxstatus[path].md5sum), binarytohex(md5sum))
								else
									modified_because = string.format("md5: (N/A) -> %s", binarytohex(md5sum))
								end
							end
							newauxstatus[path] = {size = size, md5sum = md5sum}
						end
						if really_modified then
							message.info("File '", fileinfo.path, "' was modified (", modified_because, ").")
							should_rerun = true
						else
							if CLUTTEALTEX_VERBOSITY >= 1 then
								message.info("File '", fileinfo.path, "' unmodified (size and md5sum).")
							end
						end
					else
						error(("query lfs for 'size' returned type %s"):format(type(size)))
					end
				else
					-- New file
					if path:sub(-4) == ".aux" then
						local size = filesys.attributes(path, "size")
						if size is number then
							if size == 8 then
								local auxfile = io.open(path, "rb")
								local contents = auxfile:read("*a")
								auxfile:close()
								if contents == "\\relax \n" then
									-- The .aux file is new, but it is almost empty
									else
									should_rerun = true
								end
								newauxstatus[path] = {size = size, md5sum = md5.sum(contents)}
								else
								should_rerun = true
								newauxstatus[path] = {size = size}
							end
						else
							error(("query lfs for 'size' returned type %s"):format(type(size)))
						end
					else
						should_rerun = true
					end
					if should_rerun then
						message.info("New auxiliary file '", fileinfo.path, "'.")
					else
						if CLUTTEALTEX_VERBOSITY >= 1 then
							message.info("Ignoring almost-empty auxiliary file '", fileinfo.path, "'.")
						end
					end
				end
				if should_rerun then
					break
				end
			end
		else
			-- Auxiliary file is not really a file???
		end
	end
	return should_rerun, newauxstatus
end

-- true if src is newer than dst
local function comparefiletime(srcpath:string, dstpath:string, auxstatus:{string:Module.Status}): boolean
	if not filesys.isfile(dstpath) then
		return true
	end
	local src_info = auxstatus[srcpath]
	if src_info then
		local src_mtime = src_info.mtime
		if src_mtime then
			local dst_mtime = filesys.attributes(dstpath, "modification")
			if dst_mtime is number then
				return src_mtime > dst_mtime
			else
				error(("query lfs for 'modification' returned type %s"):format(type(dst_mtime)))
			end
		end
	end
		return false
end

-- true if any of the aux/input files in filelist is newer than the reference file
local function anyNonOutputNewerThan(filelist:{Module.Filemap_ele}, reference: string): boolean
	if not filesys.isfile(reference) then
		return true
	end
	local ref_mtime = filesys.attributes(reference, "modification")
	if not ref_mtime is number then
		error(("query lfs for 'modification' returned type %s for %s"):format(type(ref_mtime), reference))
	else
		for _,f in ipairs(filelist) do
			if f.kind ~= "output" and filesys.isfile(f.abspath) then
				local f_mtime = filesys.attributes(f.abspath, "modification")
				if not f_mtime is number then
					error(("query lfs for 'modification' returned type %s for %s"):format(type(f_mtime), f.path))
				else
					if f_mtime > ref_mtime then
						return true
					end
				end
			end
		end
	end
	return false
end

local _M:Module = {
	parse_recorder_file = parse_recorder_file,
	collectfileinfo = collectfileinfo,
	comparefileinfo = comparefileinfo,
	comparefiletime = comparefiletime,
	anyNonOutputNewerThan = anyNonOutputNewerThan
}
return _M
