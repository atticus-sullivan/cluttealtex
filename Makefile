.PHONY: all checkAll doc install build

FD ?= fd

all: build doc install

build: checkAll
	eval $$(luarocks path) && cyan build
	sed -i '1s;^;#!/usr/bin/env texlua\n;' src_lua/cluttealtex.lua
	cp src_teal/texrunner/*lua src_lua/texrunner/
	cp src_teal/os_.lua src_lua/
	make -f Makefile.cluttealtex

doc:
	l3build doc

install: build
	l3build install --full

checkAll:
	eval $$(luarocks path) && cyan check $$($(FD) "\.tl" ./src_teal)
