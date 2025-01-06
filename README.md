<!-- SPDX-FileCopyrightText: 2024 - 2025 Lukas Heindl -->
<!---->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

**Note: This is a fork of [cluttex](https://github.com/minoki/cluttex) which is
using teal to transpile typed lua to classic lua.**

[![REUSE status](https://api.reuse.software/badge/git.fsfe.org/reuse/api)](https://api.reuse.software/info/git.fsfe.org/reuse/api)
[![.github/workflows/run_tests.yaml](https://github.com/atticus-sullivan/cluttealtex/actions/workflows/run_tests.yaml/badge.svg)](https://github.com/atticus-sullivan/cluttealtex/actions/workflows/run_tests.yaml)

# clutealtex

See `-h` and/or the documentation in `pdf` format.

![Example run of a simple document using cluttealtex](./demo/main.gif)

## How to install
You can either
- download the executable form the current release (`cluttealtex` or `cluttealtex.bat`)
- clone the repository and make use of the `Makefile`. Running `make install`
will use `l3build` to install the script to your `TEXMFHOME`.
- eventually I'll also publish this on ctan.org, but currently I feel this is
mostly a duplicate of `cluttex` which is already published there.

### Guide: Manual installation (on Linux)
<details><summary>Click to expand</summary>

An example how a basic installation on Linux could look like (using the latest release, not the nightly build):
```bash
V="v0.9.1" # select the version to download
baseurl="https://github.com/atticus-sullivan/cluttealtex/releases/download/${V}"

curl -o "/usr/local/bin/cluttealtex" "${baseurl}/cluttealtex"
```

This might be the simplest way of installing manually, though nicer is to setup your local \texttt{TEXMFHOME} and place the executable there.
For Linux again this could look like this:
```bash
V="v0.9.1" # select the version to download
kpsewhich --var-value TEXMFHOME # should be set to be set -> see https://tug.org/texlive/doc/texlive-en/texlive-en.html#x1-350003.4.6
baseurl="https://github.com/atticus-sullivan/cluttealtex/releases/download/${V}"
dir="$(kpsewhich --var-value TEXMFHOME)"

# install the executable
make -p "${dir}/scripts/cluttealtex"
curl -o "${dir}/scripts/cluttealtex/cluttealtex" "${baseurl}/cluttealtex"

# install the documentation -> `texdoc cluttealtex` brings up the documentation in your pdf viewer
make -p "${dir}/doc/latex/cluttealtex"
curl -o "${dir}/doc/latex/cluttealtex/cluttealtex.pdf" "${baseurl}/cluttealtex.pdf"
```

</details>

## Features
- written in / generated with `teal`/`tl? => no external dependencies, (tex)lua is
  included in more recent TeXLive installations (`TeXLive-2019` or later
  definitely works, older versions might work but were not tested)
- avoid cluttering your project directory with aux files
- watch input files and automatically rebuild on change
- run `makindex`, BibTeX, `biber` if requested
- configure manual glossaries with the `--glossaries` option
- also supports the `memoize` package. You only need to pass `--memoize` to
  `cluttealtex` and put `\usepackage{memoize}` in your LaTeX file. Also you can
  pass arbitrary additional parameters to `memoize` (useful for e.g. `readonly` key)

## Arguments
For a detailed reference, have a look at the `cluttealtex.pdf` which comes
bundled with every release.

For a short lookup you can also have a look at [this table containing all valid
arguments/options](args.md).

- `optname` refers to the name of the option when passing it via the
config file (`.cluttealtexrc.lua`)
- arguments containing `[=...]` all have a default value, so when passing this
option you don't have to specify a value. Like with usual CLI arguments, you can
pass a custom value either seperated with a space \eg `--engine lualatex`
(or seperated with an equal sign)

## For developers / advanced users
<details><summary>Click to expand</summary>

### Hooking
For some parts, cluttealtex makes use of a hooking mechanism. The initial idea
was to keep the functions in `typeset.tl` smaller and to avoid piling up code
for various options (like `glossaries` or `bibtex`/`biber`).

There are various hooks that can be installed:
- `tex_injection`: Executed prior to running the *TeX command. Used to inject
code (like `\RequirePackage`) ino the TeX input
- `suggestion_file_based`: Executed prior to running the *TeX command. If
there's a recorder file, it is parsed and this hook is used to determine whether
some options are suggested to the user.
- `post_compile`: Executed after running *TeX and the `recovery`. Used to run
external commands like `makeindex` or `biber`.
- `suggestion_execlog_based`: Executed after running *TeX. Used to suggest some
options to the user based on the log produced by *TeX.
- `post_build` Executed after *TeX produced a stable output (potentially
includes running *TeX multiple times as well as external commands). Currently
not used by cluttealtex. Idea is more to make this available to the user.

For the signature of the functions that can be used for the respective hooks,
see `option_type.tl` the `Hooks.*_func` types.

Note: All the hooks run in the typeset coroutine. They can use `coroutine.yield`
in order to run shell commands.

#### Priorities
Each hook is registered with a priority. When a certain point is reached which
can be hooked, the hooks are sorted based on the priority and executed in order.
A low number hereby means the hook is executed earlier.

The priorities used for options defined by cluttealtex are defined as constants
in `option_type.tl` in the `hook_prios` table.

Priorities are not just integers but numbers. Thus, an option gets the whole
room from `[priority,priority+1[` to install hooks to. E.g. the `memoize` option
only gets one priority and then uses different offsets for the `memoize`
(`+0.1`) and the `memoize_opts` (`+0.2`) hooks.

#### Merging Hooks
When options are passed by multiple different means (e.g. CLI + config-file),
the registered hooks get merged. This means all hooks defined in either of the
option tables is kept.

There is one exception for the hooks beginning with `suggestion_`. These are
hooks that are enabled by default and usually are disabled when an option is
set. Thus, for merging only the hooks which are defined in both option tables
are kept.

#### Suggestion Hooks
Suggestion hooks should be enabled by default. For this purpose, the
`suggestion_handlers` field in each option in the `option_spec` defines a
function for each suggestion hook which gets executed when initializing the
hooks table in the options.

</details>
