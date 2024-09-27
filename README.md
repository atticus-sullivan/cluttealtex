**Note: This is a fork of [cluttex](https://github.com/minoki/cluttex) which is
using teal to transpile typed lua to classic lua.**

# clutealtex

See `-h` and/or the documentation in `pdf` format.

## How to install
You can either
- download the executable form the current release (`cluttealtex` or `cluttealtex.bat`)
- clone the repository and make use of the `Makefile`. Running `make install`
will use `l3build` to install the script to your `TEXMFHOME`.
- eventually I'll also publish this on ctan.org, but currently I feel this is
mostly a duplicate of `cluttex` which is already published there.

## Features
- written in / generated with teal/tl => no external dependencies, (tex)lua should
  be included in texlive.
- avoid cluttering your project directory with aux files
- watch input files and automatically rebuild on change
- run `makindex`, BibTeX, `biber` if requested
- configure manual glossaries with the `--glossaries` option
- also supports the `memoize` package. You only need to pass `--memoize` to
  `cluttealtex` and put `\usepackage{memoize}` in your LaTeX file. Also you can
  pass arbitrary additional parameters to `memoize` (useful for e.g. `readonly` key)
