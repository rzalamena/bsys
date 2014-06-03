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
#  By default, if not specified, it will use the name 'default'.
#
# == Definitions
#
# name::
#  The project name. Default value is 'default'.
# pkgname<-pkgver>::
#  A package name, it must match a filename in the folder 'pkg/' without
#  the '.yml' extension.

class Project
  include Singleton

  # Read project configuration file, it's done on start-up or on reload
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

      set_project_rootdir File::join(ROOTDIR, @name)

      return
    end

    config = YAML::load_file(File::open(file))
    config.each_pair do |key, value|
      case key
      when /^name$/i
        @name           = value

        set_project_rootdir File::join(ROOTDIR, @name)
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

    if $pkglist.count == 0
      sysprint "No packages were select by the project, selecting all"
      load_all_pkg
    end

    if @name.match(/[^a-zA-Z0-9_]/)
      syserr 'Project name must not contain special characters nor spaces'
      raise
    end
  end

  # Gets project name
  def get_name
    @name
  end

private
  def load_compiler_search_path
    cflags = ''

    # Load default include folders
    cflags << "-I#{$project_rootdir}/usr/include"
    cflags << "-I#{$project_rootdir}/usr/local/include"

    # Load default lib folders
    cflags << "-L#{$project_rootdir}/lib"
    cflags << "-L#{$project_rootdir}/usr/lib"
    cflags << "-L#{$project_rootdir}/usr/local/lib"

    # Load the user configured CFLAGS
    cflags << $bsyscfg.get_cflags

    # Replay it to bsys configuration
    $bsyscfg.set_cflags cflags
  end

  def set_project_rootdir rootdir
    $project_rootdir = rootdir

    # Creates the default directory hierarchy
    create_rootdir

    # After setting the project root dir we set-up the path to it
    # so the compiler can look at its includes and libs.
    load_compiler_search_path
  end

  def validate_types
    raise "Project name must be a string" unless
      @name.is_a? String
  end
end
