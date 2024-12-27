local lester = require 'lester'

require 'specs.auxfile'
require 'specs.checkdriver'
require 'specs.fsutil'
require 'specs.handleoption'
require 'specs.option'
require 'specs.pathutil'
require 'specs.shellutil'
require 'specs.reruncheck'
require 'specs.safename'
require 'specs.tex_engine'
require 'specs.read_cfg'
require 'specs.utils'
require 'specs.watcher'

lester.report() -- Print overall statistic of the tests run.
lester.exit() -- Exit with success if all tests passed.
