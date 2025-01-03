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
