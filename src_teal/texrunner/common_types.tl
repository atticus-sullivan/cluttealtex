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
end

return Module
