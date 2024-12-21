.PHONY: all checkAll doc install build clean genArgs

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
	LUA_PATH="./src_lua/?.lua;$$LUA_PATH" lua utils/print_args.lua > args.md 2> doc/args.tex

clean:
	$(RM) -r src_lua

doc: genArgs
	l3build doc

test: build
	LUA_PATH="./src_lua/?.lua;$$LUA_PATH" texlua specs/init.lua

install: build
	l3build install --full

checkAll:
	eval $$(luarocks path) && cyan check $$($(FD) "\.tl" ./src_teal)
