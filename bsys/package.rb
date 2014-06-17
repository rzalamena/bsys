require 'yaml'

require_relative 'fetch'
require_relative 'util'

# This class defines the package parsing and behavior.
#
# = Package definition
#
# A package is created based on recipes from the directory pkg/ located
# at the top level of bsys. The package file name contains two
# informations:
# * The package name
# * Optionally the package version
#
# Example of package recipe filename: pkg/libevent-${PKGVER}.yml
#
# == Definitions
#
# Here is an example of all possible options that we can configure in a
# package: (the keywords are case insensitive)
#
#  source: ""
#  builddep:
#   - bla
#  exportdep:
#   - bla
#  bsdstyle: true|false
#  autoconfigure: true|false
#  autobuild: true|false
#  autoinstall: true|false
#  cflags: -g -pipe
#  cppflags: -O2
#  cxxflags: -O2
#  ldflags: -L/usr/lib
#  make: /usr/bin/pmake
#  jobs: 1
#  configure: |
#    ./autogen.sh
#  configure_flags: |
#    --enable-bla --feature="bla"
#  export:
#    ${SRCDIR}/headers/bla.h : /usr/include/bla.h
#  build: |
#    make build
#  install:
#    ${SRCDIR}/foo/daemon_config : /etc/daemon_config
#    ${OBJDIR}/foo/daemon : /sbin/daemon
#  install_cmd: |
#    make DESTDIR=${ROOTDIR} install
#
# === Mandatory fields
#
# source:: The package source, it might use one of the following protocols:
# * cURL
#   * FTP
#   * HTTP
#   * HTTPS
# * GIT
#   * SSH
#   * HTTPS
#
# === Default values
#
# autoconfigure::
#  Automatic configuration is *ON* by default.
# autobuild::
#  Automatic build is *ON* by default.
# autoinstall::
#  Automatic installation is *ON* by default.
# configure::
#  Empty, if +autoconfigure+ is set it is appended the automatic
#  configure procedure defined by _bsys_.
# configure_flags::
#  Empty, only used by automatic configuration procedure.
# export::
#  Empty, should be used when we want to export an early header file
#  that might be used by another packages (avoid cyclic dependencies).
# build::
#  Empty, should be used when a custom compilation command is needed.
#  If +autobuild+ is on it will be appended after this command the
#  automatic build procedure.
# install::
#  Empty, should be used when we must specify some file that is not
#  installed by the Makefile.
# install_cmd::
#  Empty, used to specify custom install command. If +autoinstall+ is on
#  then it will be appended the automatic install procedure.
# make::
#  Empty, used to specify package specific Make program
# cflags::
#  Empty, used to specify package specific C flags
# cppflags::
#  Empty, used to specify package specific C Pre Processor flags
# cxxflags::
#  Empty, used to specify package specific C++ flags
# ldflags::
#  Empty, used to specify package specific linker flags
# jobs::
#  Empty, used to specify package number of simultaneous jobs
# bsdstyle::
#  False, the default method is using autoconfiguration.

class Package
  # Initiates package constants and define package tasks.
  def initialize(pkgname)
    unless pkgname.is_a? String
      syserr 'Package name must be a string'
      raise
    end

    # Set default and create targets
    @name               = pkgname[0..-5]
    @metaname           = @name
    @version            = ''
    @fetch_url          = ''
    @configure          = ''
    @bsdstyle           = false
    @export             = Hash.new
    @build              = ''
    @install_cmd        = ''
    @install            = Hash.new
    @build_deps         = []
    @clean_deps         = []
    @autoconfigure      = true
    @autobuild          = true
    @autoinstall        = true
    @configure_flags    = ''
    @make               = ''
    @cflags             = ''
    @cppflags           = ''
    @cxxflags           = ''
    @ldflags            = ''
    @jobs               = 0

    # Detect package version through string
    smatch = @name.match(/\-\d+(\.|\d+)*.*$/)
    @version = smatch.to_s[1..-1] if smatch != nil
    if @version.length > 0
      @metaname = @name[0..- (@version.length + 2)]
    end

    if has_version?
      @srcdir = File::join(BSYS_ROOTDIR, "/src/#{@metaname}/#{@name}")
      @objdir = File::join(BSYS_ROOTDIR, "/obj/#{@metaname}/#{@name}")
    else
      @srcdir = File::join(BSYS_ROOTDIR, "/src/#{@metaname}")
      @objdir = File::join(BSYS_ROOTDIR, "/obj/#{@metaname}")
    end

    # Load package configuration
    loadpkg File::join(BSYS_ROOTDIR, "/pkg/#{pkgname}")
  end

  # Returns package name using symbol
  def getname
    return @name.to_sym
  end

  # Returns whether this package has multiple versions or not
  def has_version?
    return (@name != @metaname)
  end

  # Returns package metaname using symbol
  def getmetaname
    return @metaname.to_sym
  end

  # Generate targets and their dependencies
  def generate_targets
    has_metaname = has_version?

    %w[clean update fetch configure export build install].each do |target|
      target_name = "#{@name}_#{target}".to_sym
      target_metaname = "#{@metaname}_#{target}".to_sym if has_metaname
      func = pkg_default_target_func(@name.to_sym, target)

      task = Rake::Task.define_task(target_name, &func)
      metatask = Rake::Task.define_task(target_metaname, &func) if has_metaname

      # Add per-task dependency
      case target
      when /install/i
        task.enhance(["#{@name}_build".to_sym])
        metatask.enhance(["#{@metaname}_build".to_sym]) if has_metaname
      when /build/i
        task.enhance(["#{@name}_export".to_sym])
        metatask.enhance(["#{@metaname}_export".to_sym]) if has_metaname

        # Generate package export dependencies
        @build_deps.each do |dep|
          task.enhance(["#{dep}_export".to_sym])
          metatask.enhance(["#{dep}_export".to_sym]) if has_metaname
        end

        # Generate package build dependencies
        @clean_deps.each do |dep|
          task.enhance(["#{dep}_install".to_sym])
          metatask.enhance(["#{dep}_install".to_sym]) if has_metaname
        end
      when /export/i
        task.enhance(["#{@name}_configure".to_sym])
        metatask.enhance(["#{@metaname}_configure".to_sym]) if has_metaname
      when /configure/i
        task.enhance(["#{@name}_fetch".to_sym])
        metatask.enhance(["#{@metaname}_fetch".to_sym]) if has_metaname
      when /clean/i
        # Generate package clean dependencies
        @clean_deps.each do |dep|
          task.enhance(["#{dep}_clean".to_sym])
          metatask.enhance(["#{dep}_clean".to_sym]) if has_metaname
        end
      end

      update_global_task(target, target_name)
    end

    # Create the default package task named after the package name
    task = Rake::Task.define_task("#{@name}" => ["#{@name}_install".to_sym])
    metatask = Rake::Task.define_task("#{@metaname}" => ["#{@metaname}_install".to_sym]) if has_metaname
  end

  # Method called when the target :<pkgname>_fetch is reached
  def pkg_fetch
    return if File::exists? @srcdir

    sysprint "#{@name} fetch: #{@fetch_url}"

    # Try to guess by package URL extension
    if @fetch_url.match(/\.git$/i)
      git_clone(@fetch_url, @srcdir)
      return
    end

    # Else use the URL to select fetch method
    protocol = @fetch_url.split(':')[0]

    if protocol.length == 0
      syserr "Invalid package source URL #{@fetch_url}"
      raise
    end

    case protocol
    when /^http$/i, /^https$/i, /^ftp$/i
      curl_fetch(@fetch_url, @srcdir)
    when /git/i
      git_clone(@fetch_url, @srcdir)
    else
      syserr "Unhandled URL type: #{protocol}"
      raise
    end
  end

  # Method called when the target :<pkgname>_configure is reached
  def pkg_configure
    return if File::exists? @objdir

    sysprint "#{@name} configure"

    FileUtils::mkdir_p(@objdir)

    if @bsdstyle == true
      obj_symlink = File::join(@srcdir, 'obj')

      unless File::exists? obj_symlink
        FileUtils::ln_s(@objdir, obj_symlink)
      end
    end

    # Don't try an empty configure command
    return if @configure.length == 0

    FileUtils::cd(@objdir)

    unless sysexec @configure
      pkg_clean
      syserr "Failed to configure package"
      raise
    end

    FileUtils::cd(BSYS_ROOTDIR)
  end

  # Method called when the target :<pkgname>_export is reached
  def pkg_export
    return if @export.count == 0

    sysprint "#{@name} export"

    @export.each_pair do |src, dst|
      dst = File::join($project_rootdir, dst)
      if File::directory? src
        FileUtils::mkdir_p dst
        continue
      end

      # Create directory if it doesn't exists
      FileUtils::mkdir_p dst[0..-(File::basename(dst).length + 1)]

      if File::executable? src
        FileUtils::install(src, dst, :mode => 0755)
      else
        FileUtils::install(src, dst, :mode => 0644)
      end
    end
  end

  # Method called when the target :<pkgname>_build is reached
  def pkg_build
    sysprint "#{@name} build"

    if @bsdstyle == true
      FileUtils::cd(@srcdir)
    else
      FileUtils::cd(@objdir)
    end

    unless sysexec @build
      syserr "Failed to compile package #{@name}"
      raise
    end

    FileUtils::cd(BSYS_ROOTDIR)
  end

  # Method called when the target :<pkgname>_install is reached
  def pkg_install
    return if @install.count == 0

    sysprint "#{@name} install"

    if @install[:bsys_install] != nil
      if @bsdstyle == true
        FileUtils::cd(@srcdir)
      else
        FileUtils::cd(@objdir)
      end

      unless sysexec(@install[:bsys_install])
        syserr "Failed to install package"
        raise
      end

      FileUtils::cd(BSYS_ROOTDIR)

      @install.delete(:bsys_install)
    end

    @install.each_pair do |src, dst|
      dst = File::join($project_rootdir, dst)
      if File::directory? src
        FileUtils::mkdir_p dst
        continue
      end

      # Create directory if it doesn't exists
      FileUtils::mkdir_p dst[0..-(File::basename(dst).length + 1)]

      if File::executable? src
        FileUtils::install(src, dst, :mode => 0755)
      else
        FileUtils::install(src, dst, :mode => 0644)
      end
    end
  end

  # Method called when the target :<pkgname>_clean is reached
  def pkg_clean
    sysprint "#{@name} clean"

    FileUtils::rm_rf(@objdir, :secure => true)
  end

  # Method called when the target :<pkgname>_update is reached
  def pkg_update
    pkg_fetch unless File::exists? @srcdir

    sysprint "#{@name} update: #{@fetch_url}"

    protocol = @fetch_url.split(':')

    if protocol.length == 0
      syserr "Invalid package source URL #{@fetch_url}"
      raise
    end

    case protocol
    when /^http$/i, /^https$/i, /^ftp$/i
      sysprint "#{@name}: can't update from protocol #{protocol}"
    when /git/i
      git_update(@fetch_url)
    else
      syserr "Unhandled URL type: #{protocol}"
      raise
    end
  end

private
  def update_global_task(task, target)
    case task
    when /clean/i
      Rake::Task.define_task :clean => target
    when /update/i
      Rake::Task.define_task :update => target
    when /fetch/i
      Rake::Task.define_task :fetch => target
    when /configure/i
      Rake::Task.define_task :configure => target
    when /export/i
      Rake::Task.define_task :export => target
    when /build/i
      Rake::Task.define_task :build => target
    when /install/i
      Rake::Task.define_task :install => target
    end
  end

  # Generates and returns functions to be used by new rake targets
  def pkg_default_target_func(name, target)
    case target
    when /fetch/i
      return Proc.new {
        $pkglist[name].pkg_fetch
      }
    when /configure/i
      return Proc.new {
        $pkglist[name].pkg_configure
      }
    when /export/i
      return Proc.new {
        $pkglist[name].pkg_export
      }
    when /build/i
      return Proc.new {
        $pkglist[name].pkg_build
      }
    when /install/i
      return Proc.new {
        $pkglist[name].pkg_install
      }
    when /update/i
      return Proc.new {
        $pkglist[name].pkg_update
      }
    when /clean/i
      return Proc.new {
        $pkglist[name].pkg_clean
      }
    else
      syserr "Undefined target #{target} for package #{name.to_s}"
      raise
    end
  end

  # Returns the default package configuration instructions
  def pkg_default_configure(args='')
    <<CONFIGURE
autoreconf

CC="#{$bsyscfg.get_cc}" \\
CPP="#{$bsyscfg.get_cpp}" \\
CXX="#{$bsyscfg.get_cxx}" \\
CFLAGS="#{$bsyscfg.get_cflags} #{@cflags}" \\
CPPFLAGS="#{$bsyscfg.get_cppflags} #{@cppflags}" \\
CXXFLAGS="#{$bsyscfg.get_cxxflags} #{@cxxflags}" \\
LDFLAGS="#{$bsyscfg.get_ldflags} #{@ldflags}" \\
${SRCDIR}/configure #{args}
CONFIGURE
  end

  # Returns the default package build instructions
  def pkg_default_build
    jobnum = @jobs
    make = @make

    # If job number specification is missing, use default
    if jobnum <= 0
      jobnum = $bsyscfg.get_jobs
    end
    if make.length == 0
      make = $bsyscfg.get_make
    end

    <<BUILD
CC="#{$bsyscfg.get_cc}" \\
CPP="#{$bsyscfg.get_cpp}" \\
CXX="#{$bsyscfg.get_cxx}" \\
CFLAGS="#{$bsyscfg.get_cflags} #{@cflags}" \\
CPPFLAGS="#{$bsyscfg.get_cppflags} #{@cppflags}" \\
CXXFLAGS="#{$bsyscfg.get_cxxflags} #{@cxxflags}" \\
LDFLAGS="#{$bsyscfg.get_ldflags} #{@ldflags}" \\
#{make} -j#{jobnum}
BUILD
  end

  # Returns the default package installation instructions
  def pkg_default_install
    bsdstyle = @bsdstyle
    make = @make
    sudo_cmd = ''

    if bsdstyle == true
      sudo_cmd = 'sudo'
    end
    if make.length == 0
      make = $bsyscfg.get_make
    end

    <<INSTALL
#{sudo_cmd} #{make} DESTDIR=#{$project_rootdir}/ install
INSTALL
  end

  def replace_vars str
    return str unless str.is_a? String

    str = str.gsub(/\$\{SRCDIR\}/, @srcdir)
    str = str.gsub(/\$\{OBJDIR\}/, @objdir)
    str = str.gsub(/\$\{ROOTDIR\}/, $project_rootdir)
    str = str.gsub(/\$\{PKGNAME\}/, @metaname)
    str = str.gsub(/\$\{PKGVER\}/, @version)
  end

  def update_package_string
    @configure = replace_vars(@configure)
    @configure_flags = replace_vars(@configure_flags)
    @build = replace_vars(@build)
    @fetch_url = replace_vars(@fetch_url)

    new_hash = Hash.new
    @export.each_pair do |src, dst|
      new_hash[replace_vars(src)] = replace_vars(dst)
    end
    @export = new_hash

    new_hash = Hash.new
    @install.each_pair do |src, dst|
      new_hash[replace_vars(src)] = replace_vars(dst)
    end
    @install = new_hash
  end

  def validate_types
    raise "autoconfigure must be a boolean" unless
      is_boolean? @autoconfigure
    raise "autobuild must be a boolean" unless
      is_boolean? @autobuild
    raise "autoinstall must be a boolean" unless
      is_boolean? @autoinstall
    raise "bsdstyle must be a boolean" unless
      is_boolean? @bsdstyle

    raise "source must be a string" unless
      @fetch_url.is_a? String
    raise "export dependencies must be an array" unless
      @build_deps.is_a? Array
    raise "build dependencies must be an array" unless
      @clean_deps.is_a? Array

    raise "configure must be a string" unless
      @configure.is_a? String
    raise "configure_flags must be a string" unless
      @configure_flags.is_a? String
    raise "build must be a string" unless
      @build.is_a? String
    raise "export must be an hash" unless
      @export.is_a? Hash
    raise "install must be an hash" unless
      @install.is_a? Hash
    raise "install_cmd must be a string" unless
      @install_cmd.is_a? String

    raise "make must be a string" unless
      @make.is_a? String
    raise "cflags must be a string" unless
      @cflags.is_a? String
    raise "cppflags must be a string" unless
      @cppflags.is_a? String
    raise "cxxflags must be a string" unless
      @cxxflags.is_a? String
    raise "ldflags must be a string" unless
      @ldflags.is_a? String
    raise "jobs must be an integer" unless
      @jobs.is_a? Integer
  end

  def loadpkg(path)
    unless File::exists? path
      syserr "Failed to open #{path}"
      raise
    end

    pkg = YAML::load_file(File::open(path))

    # Search for all obligatory package configurations
    %w[source].each do |target|
      unless pkg.has_key? target
        syserr "Package '#{@name}' doesn't have key '#{target}'"
        raise
      end
    end

    # Get values from YAML configuration file
    pkg.each_pair do |key, value|
      case key
      when /^autoconfigure$/i
        @autoconfigure          = value
      when /^autobuild$/i
        @autobuild              = value
      when /^autoinstall$/i
        @autoinstall            = value
      when /^source$/i
        @fetch_url              = value
      when /^exportdep$/i
        @build_deps             = value
      when /^builddep$/i
        @clean_deps             = value
      when /^bsdstyle$/i
        @bsdstyle               = value
      when /^configure$/i
        @configure              = value
      when /^configure_flags$/i
        @configure_flags        = value
      when /^export$/i
        @export                 = value
      when /^build$/i
        @build                  = value
      when /^install$/i
        @install                = value
      when /^install_cmd$/i
        @install_cmd            = value
      when /^make$/i
        @make                   = value
      when /^cflags$/i
        @cflags                 = value
      when /^cppflags$/i
        @cppflags               = value
      when /^cxxflags$/i
        @cxxflags               = value
      when /^ldflags$/i
        @ldflags                = value
      when /^jobs$/i
        @jobs                   = value
      end
    end

    validate_types

    if @bsdstyle == true
      @autoconfigure = false
    end

    if @autoconfigure == true
      if defined? @configure
        @configure << pkg_default_configure(@configure_flags)
      else
        @configure = pkg_default_configure(@configure_flags)
      end
    end

    if @autobuild == true
      if defined? @build
        @build << pkg_default_build
      else
        @build = pkg_default_build
      end
    end

    if @autoinstall == true
      if @install_cmd.length > 0
        @install[:bsys_install] = @install_cmd
        @install[:bsys_install] << pkg_default_install
      else
        @install[:bsys_install] = pkg_default_install
      end
    end

    update_package_string
  end
end
