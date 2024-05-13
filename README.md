# cluttex_teal

See `-h` and/or the documentation in `pdf` format.

## Features
- written in /generated with teal/tl => no external dependencies, lua should be
  included in texlive.
- avoid cluttering your project directory with aux files
- watch input files and automatically rebuild on change
- run makindex, BibTeX, biber if requested
- configure manual glossaries with the `--glossaries` option
- can work together with `memoize` and allows to pass arbitrary arguments to `memoize` (useful for e.g. `readonly` key)
