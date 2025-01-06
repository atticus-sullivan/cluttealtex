-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local record Module
	record WatcherMod
		new: function(): Watcher
	end
	record Watcher_ele
		action: string
		path: string
	end
	record Watcher
		add_file: function(Watcher, string): boolean, string
		next: function(Watcher): Watcher_ele
		close: function(Watcher)
	end
end

local _M:Module = {}
return _M
