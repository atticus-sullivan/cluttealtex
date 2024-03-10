local record isatty
	isatty: function(file: FILE): boolean
	enable_virtual_terminal: function(file: FILE): boolean
end

return isatty
