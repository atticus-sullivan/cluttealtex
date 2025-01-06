-- SPDX-FileCopyrightText: 2018 ARATA Mizuki
-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

global CLUTTEALTEX_VERBOSITY: integer
local use_colors = false

local function set_colors(mode: string)
  if mode == "always" then
    local isatty = require "texrunner.isatty"
    use_colors = true
    if use_colors and isatty.enable_virtual_terminal then
      local succ = isatty.enable_virtual_terminal(io.stderr)
      if not succ and CLUTTEALTEX_VERBOSITY >= 2 then
        io.stderr:write("CluttealTeX: Failed to enable virtual terminal\n")
      end
    end
  elseif mode == "auto" then
    local isatty = require "texrunner.isatty"
    use_colors = isatty.isatty(io.stderr)
    if use_colors and isatty.enable_virtual_terminal then
      use_colors = isatty.enable_virtual_terminal(io.stderr)
      if not use_colors and CLUTTEALTEX_VERBOSITY >= 2 then
        io.stderr:write("CluttealTeX: Failed to enable virtual terminal\n")
      end
    end
  elseif mode == "never" then
    use_colors = false
  else
    error "The value of --color option must be one of 'auto', 'always', or 'never'."
  end
end

-- ESCAPE: hex 1B = dec 27 = oct 33

local CMD = {
  reset      = "\027[0m",
  underline  = "\027[4m",
  fg_black   = "\027[30m",
  fg_red     = "\027[31m",
  fg_green   = "\027[32m",
  fg_yellow  = "\027[33m",
  fg_blue    = "\027[34m",
  fg_magenta = "\027[35m",
  fg_cyan    = "\027[36m",
  fg_white   = "\027[37m",
  fg_reset   = "\027[39m",
  bg_black   = "\027[40m",
  bg_red     = "\027[41m",
  bg_green   = "\027[42m",
  bg_yellow  = "\027[43m",
  bg_blue    = "\027[44m",
  bg_magenta = "\027[45m",
  bg_cyan    = "\027[46m",
  bg_white   = "\027[47m",
  bg_reset   = "\027[49m",
  fg_x_black   = "\027[90m",
  fg_x_red     = "\027[91m",
  fg_x_green   = "\027[92m",
  fg_x_yellow  = "\027[93m",
  fg_x_blue    = "\027[94m",
  fg_x_magenta = "\027[95m",
  fg_x_cyan    = "\027[96m",
  fg_x_white   = "\027[97m",
  bg_x_black   = "\027[100m",
  bg_x_red     = "\027[101m",
  bg_x_green   = "\027[102m",
  bg_x_yellow  = "\027[103m",
  bg_x_blue    = "\027[104m",
  bg_x_magenta = "\027[105m",
  bg_x_cyan    = "\027[106m",
  bg_x_white   = "\027[107m",
}

local function exec_msg(commandline: string)
  if use_colors then
    io.stderr:write(CMD.fg_x_white, CMD.bg_red, "[EXEC]", CMD.reset, " ", CMD.fg_cyan, commandline, CMD.reset, "\n")
  else
    io.stderr:write("[EXEC] ", commandline, "\n")
  end
end

local function error_msg(...: string)
  local message = table.concat({...}, "")
  if use_colors then
    io.stderr:write(CMD.fg_x_white, CMD.bg_red, "[ERROR]", CMD.reset, " ", CMD.fg_red, message, CMD.reset, "\n")
  else
    io.stderr:write("[ERROR] ", message, "\n")
  end
end

local function warn_msg(...: string)
  local message = table.concat({...}, "")
  if use_colors then
    io.stderr:write(CMD.fg_x_white, CMD.bg_red, "[WARN]", CMD.reset, " ", CMD.fg_blue, message, CMD.reset, "\n")
  else
    io.stderr:write("[WARN] ", message, "\n")
  end
end

local function diag_msg(...: string)
  local message = table.concat({...}, "")
  if use_colors then
    io.stderr:write(CMD.fg_x_white, CMD.bg_red, "[DIAG]", CMD.reset, " ", CMD.fg_blue, message, CMD.reset, "\n")
  else
    io.stderr:write("[DIAG] ", message, "\n")
  end
end

local function info_msg(...: string)
  local message = table.concat({...}, "")
  if use_colors then
    io.stderr:write(CMD.fg_x_white, CMD.bg_red, "[INFO]", CMD.reset, " ", CMD.fg_magenta, message, CMD.reset, "\n")
  else
    io.stderr:write("[INFO] ", message, "\n")
  end
end

global CLUTTEALTEX_TEST_ENV: boolean
if CLUTTEALTEX_TEST_ENV then
	return {
		set_colors = function(...:any) end,
		exec  = function(...:any) end,
		error = function(...:any) end,
		warn  = function(...:any) end,
		diag  = function(...:any) end,
		info  = function(...:any) end,
	}
else
	return {
		set_colors = set_colors,
		exec  = exec_msg,
		error = error_msg,
		warn  = warn_msg,
		diag  = diag_msg,
		info  = info_msg,
	}
end
