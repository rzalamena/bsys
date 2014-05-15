require 'yaml'

# This class defines the configuration parser and a singleton that
# stores the bsys configuration used by all modules.
#
# = Configuration
#
# Here is an example of all possibles configuration that we can make:
#
#  CC: /usr/bin/cc
#  CPP: /usr/bin/g++
#  CFLAGS: -g
#  CPPFLAGS: -g
#  JOBS: 3

class Configuration
  include Singleton

  def validate_types
    raise "CC configuration must be a string" unless
      @cc.is_a? String
    raise "CPP configuration must be a string" unless
      @cpp.is_a? String
    raise "CFLAGS configuration must be a string" unless
      @cflags.is_a? String
    raise "CPPFLAGS configuration must be a string" unless
      @cppflags.is_a? String
    raise "JOB configuration must be an integer" unless
      @jobs.is_a? Integer
  end

  def read_config(file)
    unless file.is_a? String
      syserr 'Configuration file name must be a string'
      raise
    end

    # Create and set defaults values
    @cc         = 'gcc'
    @cpp        = 'g++'
    @jobs       = 1
    @cflags     = ''
    @cppflags   = ''

    # Exit if file doesn't exists
    return unless File::exists? file

    config = YAML::load_file(File::open(file))
    config.each_pair do |key, value|
      case key
      when /cc/i
        @cc             = value
      when /cpp/i
        @cpp            = value
      when /cflags/i
        @cflags         = value
      when /cppflags/i
        @cppflags       = value
      when /jobs/i
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

  def get_cflags
    @cflags
  end

  def get_cppflags
    @cppflags
  end

  def get_jobs
    @jobs
  end
end
