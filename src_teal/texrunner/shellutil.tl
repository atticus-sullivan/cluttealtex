--[[
  Copyright 2016 ARATA Mizuki
  Copyright 2024 Lukas Heindl

  This file is part of ClutTeX_teal.

  ClutTeX_teal is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  ClutTeX_teal is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with ClutTeX_teal.  If not, see <http://www.gnu.org/licenses/>.
]]

-- This module provides: shellutil.escape(s)

local os = require "os_"

if os.type == "windows" then
  return require("texrunner.shellutil_windows")
else
  return require("texrunner.shellutil_unix")
end
