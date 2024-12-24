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

lester.report() -- Print overall statistic of the tests run.
lester.exit() -- Exit with success if all tests passed.
