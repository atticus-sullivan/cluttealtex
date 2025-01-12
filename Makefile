.PHONY: all checkAll doc install build clean genArgs release releasePre releasePost genDemo

FD ?= fd

all: build test doc install genArgs

build: clean checkAll
	@cyan version
	mkdir -p src_lua/texrunner
	cd src_teal && $(FD) "\.lua" . --exec cp {} ../src_lua/{}
	@cyan version
	eval $$(luarocks path) && cyan build
	sed -i '1s;^;#!/usr/bin/env texlua\n;' src_lua/cluttealtex.lua
	cp src_teal/texrunner/*lua src_lua/texrunner/
	cp src_teal/os_.lua src_lua/
	make -f Makefile.cluttealtex

genArgs: build
	LUA_PATH="./src_lua/?.lua;$$LUA_PATH" texlua utils/print_args.lua > args.md 2> doc/args.tex

genDemo: build
	cd demo && vhs main.tape

clean:
	$(RM) -r src_lua
	l3build clean

doc: genArgs
	l3build doc

test: build
	LUA_PATH="./src_lua/?.lua;$$LUA_PATH" texlua specs/init.lua

install: build
	l3build install --full

checkAll:
	eval $$(luarocks path) && cyan check $$($(FD) "\.tl" ./src_teal)

release: releasePre

releasePre: clean checkAll build test doc
	# check if git is in a clean state
	git update-index --refresh
	git diff-index --quiet HEAD --
	# check if on main branch
	test $(shell git rev-parse --abbrev-ref HEAD) == "main"
	@echo -e "\n"
	# list all TODOs related to a new release
	grep --exclude-dir '.git' --exclude-dir 'src_lua' --exclude-dir 'build' --exclude 'Makefile' --color=always -r "TODO(release)" .
	@echo -e "\n"
	read -p "Check that version numbers are correct" muell
	make releasePost

releasePost: clean checkAll build test doc
	# check if git is in a clean state
	git update-index --refresh
	git diff-index --quiet HEAD --
	# check if on main branch
	test $(shell git rev-parse --abbrev-ref HEAD) == "main"
	read -i "$$(git describe --tags --abbre=0)" -p "Enter release number (last was $$(git describe --tags --abbre=0)): " tag && git tag "$${tag}" && git push origin "$${tag}"
