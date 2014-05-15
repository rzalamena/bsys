require 'yaml'

require_relative 'fetch'
require_relative 'util'

# Is used to determine if a var is a boolean
def is_boolean? arg
  if arg.is_a? TrueClass or arg.is_a? FalseClass
    return true
  else
    return false
  end
end

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
# Example of package recipe filename: pkg/libevent-2.0.22-stable.yml
#
# == Definitions
#
# Here is an example of all possible options that we can configure in a
# package:
#
#  source: ""
#  builddep:
#   - bla
#  exportdep:
#   - bla
#  autoconfigure: true|false
#  autobuild: true|false
#  autoinstall: true|false
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
    @export             = Hash.new
    @build              = ''
    @install_cmd        = ''
    @install            = Hash.new
    @build_deps         = []
    @clean_deps         = []

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

    %w[fetch configure export build install].each do |target|
      target_name = "#{@name}_#{target}".to_sym
      target_metaname = "#{@metaname}_#{target}".to_sym if has_metaname
      func = pkg_default_target_func(@name, target)

      task = Rake::Task.define_task(target_name, &func)
      metatask = Rake::Task.define_task(target_metaname, &func) if has_metaname

      # Generate package export dependencies
      if target == 'build' and defined? @build_deps
        @build_deps.each do |dep|
          task.enhance("#{dep}_export".to_sym)
          metatask.enhance("#{dep}_export".to_sym) if has_metaname
        end
        @clean_deps.each do |dep|
          task.enhance("#{dep}_build".to_sym)
          metatask.enhance("#{dep}_build".to_sym) if has_metaname
        end
      end
    end
  end

  # Method called when the target :<pkgname>_fetch is reached
  def pkg_fetch
    return if File::exists? @srcdir

    sysprint "#{@name} fetch: #{@fetch_url}"

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
      dst = File::join(ROOTDIR, dst)
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

    FileUtils::cd(@objdir)

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
      FileUtils::cd(@objdir)

      sysexec(@install[:bsys_install])

      FileUtils::cd(BSYS_ROOTDIR)

      @install.delete(:bsys_install)
    end

    @install.each_pair do |src, dst|
      dst = File::join(ROOTDIR, dst)
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
  # Generates and returns functions to be used by new rake targets
  def pkg_default_target_func(name, target)
    case target
    when /fetch/i
      return Proc.new {
        pkglist[name].pkg_fetch
      }
    when /configure/i
      return Proc.new {
        pkglist[name].pkg_configure
      }
    when /export/i
      return Proc.new {
        pkglist[name].pkg_export
      }
    when /build/i
      return Proc.new {
        pkglist[name].pkg_build
      }
    when /install/i
      return Proc.new {
        pkglist[name].pkg_install
      }
    when /update/i
      return Proc.new {
        pkglist[name].pkg_update
      }
    when /clean/i
      return Proc.new {
        pkglist[name].pkg_clean
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

${SRCDIR}/configure #{args}
CONFIGURE
  end

  # Returns the default package build instructions
  def pkg_default_build(jobnum=1)
    <<BUILD
make -j#{jobnum}
BUILD
  end

  # Returns the default package installation instructions
  def pkg_default_install
    <<INSTALL
make DESTDIR=#{ROOTDIR}/ install
INSTALL
  end

  def replace_vars str
    return str unless str.is_a? String

    str = str.gsub(/\$\{SRCDIR\}/, @srcdir)
    str = str.gsub(/\$\{OBJDIR\}/, @objdir)
    str = str.gsub(/\$\{ROOTDIR\}/, ROOTDIR)
    str = str.gsub(/\$\{PKGNAME\}/, @metaname)
    str = str.gsub(/\$\{PKGVER\}/, @version)
  end

  def update_package_string
    @configure = replace_vars(@configure)
    @configure_flags = replace_vars(@configure_flags)
    @build = replace_vars(@build)

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
    raise "export must be an array" unless
      @export.is_a? Hash
    raise "install must be an array" unless
      @install.is_a? Hash
    raise "install_cmd must be a string" unless
      @install_cmd.is_a? String
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
    @autoconfigure      = true
    @autobuild          = true
    @autoinstall        = true
    @configure_flags    = ''
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
      end
    end

    unless @fetch_url.match(/:\/\//)
      syserr "Invalid package source URL: #{@fetch_url}: expected TYPE://URL"
      raise
    end

    validate_types

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
