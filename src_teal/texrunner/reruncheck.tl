-- SPDX-FileCopyrightText: 2016 - 2018 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local io = io
local assert = assert
local filesys = require "lfs"
local md5 = require "md5"
local fsutil = require "texrunner.fsutil"
local pathutil = require "texrunner.pathutil"
local message = require "texrunner.message"
local option_t = require "texrunner.option_type"
local common_t = require "texrunner.common_types"

local exit: function(code:integer)
global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	exit = function(code) error("exited with exitcode "..tostring(code)) end
else
	exit = os.exit
end

-- Module structure defining records and exported functions
local record Module
	-- Record type for file attributes (modification time and size)
	record fileAttrs
		mtime: number
		size:  number
	end

	parse_recorder_file: function(string, option_t.Options, ?{common_t.Filemap_ele}, ?{string:common_t.Filemap_ele}): {common_t.Filemap_ele}, {string:common_t.Filemap_ele}
	collectfileinfo: function({common_t.Filemap_ele}, {string:common_t.Status}): {string:common_t.Status}
	comparefileinfo: function({common_t.Filemap_ele}, {string:common_t.Status}): boolean, {string:common_t.Status}
	comparefiletime: function(string, string, {string:common_t.Status}): boolean
	anyNonOutputNewerThan: function(filelist:{common_t.Filemap_ele}, reference: string): boolean

	_internal: Internal
	record Internal
		md5sum_file:          function(path:string): string
		binarytohex:          function(s:string): string
		get_file_attributes:  function(path: string, get_mtime:boolean, get_size:boolean): fileAttrs
		get_output_file_kind: function(ext: string, options: option_t.Options): common_t.FileKind
		get_input_file_kind:  function(ext: string, options: option_t.Options): common_t.FileKind
		check_input_file:     function(path: string, fileinfo: common_t.Filemap_ele, auxstatus: {string: common_t.Status}): boolean, common_t.Status
		check_auxiliary_file: function(path: string, fileinfo: common_t.Filemap_ele, auxstatus: {string: common_t.Status}): boolean, common_t.Status
		parse_recorder_line:  function(line: string, options: option_t.Options, filelist: {common_t.Filemap_ele}, filemap: {string: common_t.Filemap_ele})
	end
end

-- Calculate the MD5 checksum of a file
local function md5sum_file(path:string): string
	local f = assert(io.open(path, "rb"))
	local contents = f:read("*a")
	f:close()
	return md5.sum(contents)
end

-- Convert a binary string to a hexadecimal representation
local function binarytohex(s:string): string
	local r = s:gsub(".", function(c:string): string
		local r = string.format("%02x", string.byte(c))
		return r
	end)
	return r
end

-- Fetch file attributes (mtime, size)
local function get_file_attributes(path: string, get_mtime:boolean, get_size:boolean): Module.fileAttrs
	local mtime, size: any, any

	if get_mtime then
		mtime = filesys.attributes(path, "modification")
		if mtime and not mtime is number then
			error(("query lfs for 'modification' returned type %s for %s"):format(type(mtime), path))
		end
	end

	if get_size then
		size = filesys.attributes(path, "size")
		if size and not size is number then
			error(("query lfs for 'size' returned type %s for %s"):format(type(size), path))
		end
	end

	return {mtime = mtime as number, size = size as number}
end

-- Determine the kind of an output file based on its extension and options
local function get_output_file_kind(ext: string, options: option_t.Options): common_t.FileKind
	if ext == "out" then
		return "auxiliary" -- hyperref bookmarks
	elseif options.makeindex and ext == "idx" then
		return "auxiliary" -- MakeIndex input
	elseif ext == "bcf" then
		return "auxiliary" -- biber
	elseif ext == "sage" then
		return "auxiliary" -- sagetex
	elseif ext == "mmz" or ext == "memo" then
		return "auxiliary" -- memoize
	elseif options.glossaries then
		for _, glossary in ipairs(options.glossaries) do
			if ext == glossary.inp then
				return "auxiliary"
			end
		end
	end
	return "output"
end

-- Determine the kind of an input file based on its extension and options
local function get_input_file_kind(ext: string, options: option_t.Options): common_t.FileKind
	if ext == "bbl" then
		return "auxiliary"
	elseif options.glossaries then
		for _, glossary in ipairs(options.glossaries) do
			if ext == glossary.out then
				return "auxiliary"
			end
		end
	end
	return "input"

end

-- Parse a single line from the recorder file
local function parse_recorder_line(line: string, options: option_t.Options, filelist: {common_t.Filemap_ele}, filemap: {string: common_t.Filemap_ele})
	local t, path = line:match("^(%w+) (.*)$")
	if not t or not path then
		message.warn("Unrecognized line in recorder file: ", line)
		return
	end

	if t == "PWD" then
		-- Ignore PWD lines
		return
	elseif not(t == "INPUT" or t == "OUTPUT") then
		message.warn("Unrecognized line in recorder file: ", line)
		return
	end

	-- Parse file type and initialize/update file records
	local abspath = pathutil.abspath(path)
	local ext = pathutil.ext(path)
	local fileinfo = filemap[abspath]

	local kind:common_t.FileKind
	if t == "INPUT" then
		kind = get_input_file_kind(ext, options)
	else
		kind = get_output_file_kind(ext, options)
	end

	if not fileinfo then
		-- Initialize fileinfo if it doesn't exist
		if fsutil.isfile(path) or t == "OUTPUT" then
			fileinfo = {path = path, abspath = abspath, kind = kind}
			table.insert(filelist, fileinfo)
			filemap[abspath] = fileinfo
		end
	else
		-- Update existing fileinfo
		if #path < #fileinfo.path then
			fileinfo.path = path
		end
		if (t == "INPUT" and fileinfo.kind == "output") or (t == "OUTPUT" and fileinfo.kind == "input") then
			-- The files listed in both INPUT and OUTPUT are considered to be auxiliary files.
			fileinfo.kind = "auxiliary"
		end
	end
end

-- Parse the recorder file and build file lists/maps
local function parse_recorder_file(file: string, options: option_t.Options, filelist?: {common_t.Filemap_ele}, filemap?: {string: common_t.Filemap_ele}): {common_t.Filemap_ele}, {string: common_t.Filemap_ele}
	-- init
	filelist = filelist or {}
	filemap = filemap or {}

	for line in io.lines(file) do
		parse_recorder_line(line, options, filelist, filemap)
	end

	return filelist, filemap
end

-- Collect information about files in the file list
local function collectfileinfo(filelist:{common_t.Filemap_ele}, auxstatus:{string:common_t.Status}): {string:common_t.Status}
	auxstatus = auxstatus or {}

	for _,fileinfo in ipairs(filelist) do
		local path = fileinfo.abspath

		if fsutil.isfile(path) then
			local status = auxstatus[path] or {}
			auxstatus[path] = status

			if fileinfo.kind == "input" then
				local attrs = get_file_attributes(path, status.mtime == nil, false)
				status.mtime = status.mtime or attrs.mtime

			elseif fileinfo.kind == "auxiliary" then
				local attrs = get_file_attributes(path, status.mtime == nil, status.size == nil)
				status.mtime  = status.mtime or attrs.mtime
				status.size  = status.size or attrs.size
				status.md5sum = status.md5sum or md5sum_file(path)
			end
		end
	end
	return auxstatus
end

-- Check if an input file has been updated
local function check_input_file(path: string, fileinfo: common_t.Filemap_ele, auxstatus: {string: common_t.Status}): boolean, common_t.Status
	local attrs = get_file_attributes(path, true, false)
	local mtime = attrs.mtime

	local status = auxstatus[path]
	if status and status.mtime and status.mtime < mtime then
		-- Input file was updated during execution
		message.info("Input file '", fileinfo.path, "' was modified (by user, or some external commands).")
		return true, {mtime = mtime}
	end

	return false, {mtime = mtime}
end

-- Check if an auxiliary file has been modified
local function check_auxiliary_file(path: string, fileinfo: common_t.Filemap_ele, auxstatus: {string: common_t.Status}): boolean, common_t.Status
	local status = auxstatus[path]
	if status then
		-- Handle size and MD5 changes
		local really_modified = false
		local modified_because:string = nil

		local attrs = get_file_attributes(path, false, true)
		local size = attrs.size

		if status.size ~= size then
			really_modified = true
			modified_because = string.format("size: %s -> %d", tostring(status.size) or "(N/A)", size)
			status = {size = size}
		else
			local md5sum = md5sum_file(path)
			if status.md5sum ~= md5sum then
				really_modified = true
				modified_because = string.format("md5: %s -> %s", status.md5sum and binarytohex(status.md5sum) or "(N/A)", binarytohex(md5sum))
			end
			status = {size = size, md5sum = md5sum}
		end

		if really_modified then
			message.info("File '", fileinfo.path, "' was modified (", modified_because, ").")
			return true, status
		elseif CLUTTEALTEX_VERBOSITY >= 2 then
			message.info("File '", fileinfo.path, "' unmodified (size and md5sum).")
		end
	else
		-- New auxiliary file detected
		status = {}
		local should_rerun = false
		if path:sub(-4) == ".aux" then
			local attrs = get_file_attributes(path, false, true)
			local size = attrs.size

			if size == 8 then
				local auxfile = io.open(path, "rb")
				local contents = auxfile:read("*a")
				auxfile:close()
				if contents == "\\relax \n" then
					-- The .aux file is new, but it is almost empty
				else
					should_rerun = true
				end
				status = {size = size, md5sum = md5.sum(contents)}
			else
				should_rerun = true
				status = {size = size}
			end
		else
			should_rerun = true
		end

		if should_rerun then
			message.info("New auxiliary file '", fileinfo.path, "'.")
			return true, status
		else
			if CLUTTEALTEX_VERBOSITY >= 1 then
				message.info("Ignoring almost-empty auxiliary file '", fileinfo.path, "'.")
			end
		end
	end

	return false, status
end

-- Compare file information for changes
local function comparefileinfo(filelist: {common_t.Filemap_ele}, auxstatus: {string: common_t.Status}): boolean, {string: common_t.Status}
	local newauxstatus: {string: common_t.Status} = {}

	for _, fileinfo in ipairs(filelist) do
		local path = fileinfo.abspath
		if not fsutil.isfile(path) then
			goto continue
		end

		if fileinfo.kind == "input" then
			-- Input file: User might have modified while running TeX.
			local rerun, updated_status = check_input_file(path, fileinfo, auxstatus)
			if rerun then
				newauxstatus[path] = updated_status
				return true, newauxstatus
			end

			elseif fileinfo.kind == "auxiliary" then
			local rerun, updated_status = check_auxiliary_file(path, fileinfo, auxstatus)
			if rerun then
				newauxstatus[path] = updated_status
				return true, newauxstatus
			else
				newauxstatus[path] = updated_status
			end
		end
		::continue::
	end
	return false, newauxstatus
end

-- Check if one file is newer than another
local function comparefiletime(srcpath:string, dstpath:string, auxstatus:{string:common_t.Status}): boolean
	if not fsutil.isfile(dstpath) then
		return true
	end
	local src_info = auxstatus[srcpath]
	if src_info then
		local src_mtime = src_info.mtime
		if src_mtime then
			local attr = get_file_attributes(dstpath, true, false)
			local dst_mtime = attr.mtime
			return src_mtime > dst_mtime
		end
	end
	return false
end

-- Check if any file in the list is newer than a reference file
local function anyNonOutputNewerThan(filelist:{common_t.Filemap_ele}, reference: string): boolean
	if not fsutil.isfile(reference) then
		return true
	end
	local attrs = get_file_attributes(reference, true, false)
	local ref_mtime = attrs.mtime
	for _,f in ipairs(filelist) do
		if f.kind ~= "output" and fsutil.isfile(f.abspath) then
			local f_attrs = get_file_attributes(f.abspath, true, false)
			local f_mtime = f_attrs.mtime
			if f_mtime > ref_mtime then
				return true
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

if CLUTTEALTEX_TEST_ENV then
	_M._internal = {
		md5sum_file           = md5sum_file,
		binarytohex           = binarytohex,
		get_file_attributes   = get_file_attributes,
		get_output_file_kind  = get_output_file_kind,
		get_input_file_kind   = get_input_file_kind,
		parse_recorder_line   = parse_recorder_line,
		check_input_file      = check_input_file,
		check_auxiliary_file  = check_auxiliary_file,
	}
end

return _M
