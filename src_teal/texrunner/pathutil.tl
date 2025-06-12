-- SPDX-FileCopyrightText: 2016 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local os = require "os_"

if os.type == "windows" then
  return require("texrunner.pathutil_windows")
else
  return require("texrunner.pathutil_unix")
end
