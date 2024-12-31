local record Module
	record Filemap_ele
		path: string
		abspath: string
		kind: FileKind
	end
	-- Enum representing types of files handled by the module
	enum FileKind
		"auxiliary"
		"output"
		"input"
	end
	record Status
		mtime: number
		size: number
		md5sum: string
	end
	type filelist = {Filemap_ele}
	type auxstatus = {string: Status}
end

return Module
