require 'yaml'

# This class defines the configuration parser and a singleton that
# stores the bsys configuration used by all modules.
#
# = Configuration
#
# Here is an example of all possibles configuration that we can make:
#
#  CC: /usr/bin/cc
#  CPP: /usr/bin/cpp
#  CXX: /usr/bin/c++
#  CFLAGS: -g
#  CPPFLAGS: -g
#  CXXFLAGS: -g
#  JOBS: 3
#
# There are no mandatory configurations now.
#
# == Definitions
#
# CC::
#  The location of the C compiler that we are going to use.
# CPP::
#  The location of the C Pre Processor that we are going to use.
# CXX::
#  The location of the C++ compiler that we are going to use.
# CFLAGS::
#  The C compiler flags
# CPPFLAGS::
#  The C Pre Processor flags
# CXXFLAGS::
#  The C++ flags that we are going to use
# JOBS::
#  The concurrent number of jobs that we are going to run the
#  compilations (the '-j#' option)

class Configuration
  include Singleton

  def validate_types
    raise "CC configuration must be a string" unless
      @cc.is_a? String
    raise "CPP configuration must be a string" unless
      @cpp.is_a? String
    raise "C++ configuration must be a string" unless
      @cxx.is_a? String
    raise "CFLAGS configuration must be a string" unless
      @cflags.is_a? String
    raise "CPPFLAGS configuration must be a string" unless
      @cppflags.is_a? String
    raise "CXXFLAGS configuration must be a string" unless
      @cxxflags.is_a? String
    raise "JOB configuration must be an integer" unless
      @jobs.is_a? Integer
  end

  def read_config(file)
    unless file.is_a? String
      syserr 'Configuration file name must be a string'
      raise
    end

    # Create and set defaults values
    @cc         = 'cc'
    @cpp        = 'cpp'
    @cxx        = 'c++'
    @jobs       = 1
    @cflags     = ''
    @cppflags   = ''
    @cxxflags   = ''

    # Exit if file doesn't exists
    return unless File::exists? file

    config = YAML::load_file(File::open(file))
    config.each_pair do |key, value|
      case key
      when /^cc$/i
        @cc             = value
      when /^cpp$/i
        @cpp            = value
      when /^c\+\+$/i, /^cxx$/i
        @cxx            = value
      when /^cflags$/i
        @cflags         = value
      when /^cppflags$/i
        @cppflags       = value
      when /^cxxflags$/i
        @cxxflags       = value
      when /^jobs$/i
        @jobs           = value
      end
    end

    validate_types
  end

  def get_cc
    @cc
  end

  def get_cpp
    @cpp
  end

  def get_cxx
    @cxx
  end

  def get_cflags
    @cflags
  end

  def get_cppflags
    @cppflags
  end

  def get_cxxflags
    @cxxflags
  end

  def get_jobs
    @jobs
  end
end
