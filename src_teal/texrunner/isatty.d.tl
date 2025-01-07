-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local record isatty
	isatty: function(file: FILE): boolean
	enable_virtual_terminal: function(file: FILE): boolean
end

return isatty
