-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl
--
-- SPDX-License-Identifier: GPL-3.0-or-later

module       = "cluttealtex"
typesetexe   = "lualatex"
typesetfiles = {"cluttealtex.tex"}
docfiles     = {"args.tex"}

unpackexe    = "luatex"
unpackfiles  = {}
docfiledir   = "./doc"

scriptfiles  = {"cluttealtex", "cluttealtex.bat"}
sourcefiles  = {"bin/cluttealtex", "bin/cluttealtex.bat"}

excludefiles = {".link.md", "*~", "build.lua"}
