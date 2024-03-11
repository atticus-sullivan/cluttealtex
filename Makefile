.PHONY: all checkAll doc install build

all: build doc install

build: checkAll
	eval $$(luarocks path) && tl build
	sed -i '1s;^;#!/usr/bin/env texlua\n;' src_lua/cluttex_teal.lua
	cp src_teal/texrunner/*lua src_lua/texrunner/
	cp src_teal/os_.lua src_lua/
	make -f Makefile.cluttex_teal

doc:
	l3build doc

install:
	l3build install

checkAll:
	eval $$(luarocks path) && tl check $$(fd "\.tl" ./src_teal)
