# bsys - Build System
#
# This is a free and simple build system focused on getting things done.
#
# Author::    Rafael Zalamena (mailto:rzalamena@gmail.com)
# Copyright:: Copyright (c) 2014
# License::   ISC License

require_relative 'config'
require_relative 'package'
require_relative 'util'

# Constant string that points to the root directory of bsys
BSYS_ROOTDIR=Dir::getwd

# Constant that defines the path to root directory
ROOTDIR=File::join(BSYS_ROOTDIR, 'root')

# Constant string that defines the location of the default bsys
# configuration
BSYS_DEFAULT_CONFIG=File::join(BSYS_ROOTDIR, 'configuration.yml')

# Constant that points to the download folder
DISTFILES = File::join(BSYS_ROOTDIR, "/distfiles")

$bsyscfg = Configuration.instance
$bsyscfg.read_config BSYS_DEFAULT_CONFIG
