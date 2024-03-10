
local record Module
	record WatcherMod
		new: function(): Watcher
	end
	record Watcher_ele
		action: string
		path: string
	end
	record Watcher
		add_file: function(Watcher, string)
		next: function(Watcher): Watcher_ele
		close: function(Watcher)
		-- TODO function definition
	end
end

local _M:Module = {}
return _M
