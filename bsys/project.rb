require 'yaml'

require_relative 'util'

# This class defines the project parser and a singleton that
# stores the bsys actual project configuration.
#
# = The project file
#
# Here is an example of all possibles project configuration that we can
# make:
#
#  name: projectname
#  libevent-2.0.21-stable: true
#
# == Mandatory fields
#
# name::
#  Project name is mandatory, it will be used to create the root
#  directory. It should not contain spaces or any special caracter.
#  Basically it will only accept the following regex: [a-zA-Z0-9_].
#
# == Definitions
#
# name::
#  The project name
# pkgname<-pkgver>::
#  A package name, it must match a filename in the folder 'pkg/' without
#  the '.yml' extension.

class Project
  include Singleton

  def read_config(file)
    unless file.is_a? String
      syserr 'Project file name must be a string'
      raise
    end

    # Create and set defaults values
    @name       = 'default'

    # Exit if file doesn't exists
    unless File::exists? file
      if $pkglist.count == 0
        sysprint "No packages were select by the project, selecting all"
        load_all_pkg
      end

      $project_rootdir = File::join(ROOTDIR, @name)

      return
    end

    config = YAML::load_file(File::open(file))
    config.each_pair do |key, value|
      case key
      when /^name$/i
        @name           = value
      else
        unless is_boolean? value
          syserr "Package #{key} must have value true or false"
          raise
        end

        # Skip package if not selected
        next unless value == true

        load_pkg(key)
      end
    end

    validate_types

    $project_rootdir = File::join(ROOTDIR, @name)

    if $pkglist.count == 0
      sysprint "No packages were select by the project, selecting all"
      load_all_pkg
    end

    if @name.match(/[^a-zA-Z0-9_]/)
      syserr 'Project name must not contain special characters nor spaces'
      raise
    end
  end

  def get_name
    @name
  end

private
  def validate_types
    raise "Project name must be a string" unless
      @name.is_a? String
  end
end
