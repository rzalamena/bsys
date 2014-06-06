require 'yaml'

# This class defines the configuration parser and a singleton that
# stores the bsys configuration used by all modules.
#
# = Configuration
#
# Here is an example of all possibles configuration that we can make:
# (the configuration keywords are case insensitive)
#
#  MAKE: /usr/bin/make
#  CC: /usr/bin/cc
#  CPP: /usr/bin/cpp
#  CXX: /usr/bin/c++
#  CFLAGS: -g
#  CPPFLAGS: -g
#  CXXFLAGS: -g
#  LDFLAGS: -L/usr/lib
#  JOBS: 3
#
# There are no mandatory configurations now.
#
# == Definitions
#
# MAKE::
#  The location of the Make program that we are going to use.
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

  # Loads configuration from file 'configuration.yml'. By default this
  # file is non-existent and it should be created by the user.
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
    @ldflags    = ''
    @make       = 'make'

    # Exit if file doesn't exists
    return unless File::exists? file

    config = YAML::load_file(File::open(file))
    config.each_pair do |key, value|
      case key
      when /^make$/i
        @make           = value
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
      when /^ldflags$/i
        @ldflags        = value
      when /^jobs$/i
        @jobs           = value
      end
    end

    validate_types
  end

  # Get Make program
  def get_make
    @make
  end

  # Get C Compiler
  def get_cc
    @cc
  end

  # Get C Pre Processor
  def get_cpp
    @cpp
  end

  # Get C++ compiler
  def get_cxx
    @cxx
  end

  # Get C compiler flags
  def get_cflags
    @cflags
  end

  # Get C Pre Processor flags
  def get_cppflags
    @cppflags
  end

  # Get C++ compiler flags
  def get_cxxflags
    @cxxflags
  end

  # Get linker flags
  def get_ldflags
    @ldflags
  end

  # Get job number configuration
  def get_jobs
    @jobs
  end

  # Set new CFLAGS.
  #
  # Currently being used by class Project to load the flags for
  # searching includes and libraries from project ROOTDIR.
  def set_cflags cflags
    @cflags = cflags
  end

  # Set new LDFLAGS.
  #
  # Currently being used by class Project to load the flags for
  # searching includes and libraries from project ROOTDIR.
  def set_ldflags ldflags
    @ldflags = ldflags
  end

private
  def validate_types
    raise "MAKE configuration must be a string" unless
      @make.is_a? String
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
    raise "LDFLAGS configuration must be a string" unless
      @ldflags.is_a? String
    raise "JOB configuration must be an integer" unless
      @jobs.is_a? Integer
  end
end
