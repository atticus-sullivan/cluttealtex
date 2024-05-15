**Note: This is a fork of [cluttex](https://github.com/minoki/cluttex) which is
using teal to transpile typed lua to classic lua.**

# cluttex_teal

See `-h` and/or the documentation in `pdf` format.

## Features
- written in /generated with teal/tl => no external dependencies, lua should be
  included in texlive.
- avoid cluttering your project directory with aux files
- watch input files and automatically rebuild on change
- run `makindex`, BibTeX, `biber` if requested
- configure manual glossaries with the `--glossaries` option
- also supports the `memoize` package. You only need to pass `--memoize` to
  `cluttex_teal` and put `\usepackage{memoize}` in your LaTeX file. Also you can
  pass arbitrary additional parameters to `memoize` (useful for e.g. `readonly` key)
