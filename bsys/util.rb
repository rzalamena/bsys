# :nodoc:

# Text colors
TC_BLACK=1
TC_RED=2
TC_GREEN=3
TC_YELLOW=4
TC_BLUE=5
TC_MAGENTA=6
TC_CYAN=7
TC_WHITE=8

# Background colors
BC_BLACK=1
BC_RED=2
BC_GREEN=3
BC_YELLOW=4
BC_BLUE=5
BC_MAGENTA=6
BC_CYAN=7
BC_WHITE=8

# :doc:

# Is used to determine if a var is a boolean
def is_boolean? arg
  if arg.is_a? TrueClass or arg.is_a? FalseClass
    return true
  else
    return false
  end
end

# Reset text output formating
def resetformat
  return "\e[0m"
end

# Turns text bold
def boldnize(enable)
  return "\e[1m"
end

# Underlines texts
def underlinenize(enable)
  return "\e[4m"
end

# Add foreground and optionally background color
def colorize(fcode, bcode=0)
  str = "\e["

  case fcode
  when TC_BLACK
    str << '30'
  when TC_RED
    str << '31'
  when TC_GREEN
    str << '32'
  when TC_YELLOW
    str << '32'
  when TC_BLUE
    str << '32'
  when TC_MAGENTA
    str << '32'
  when TC_CYAN
    str << '32'
  when TC_WHITE
    str << '32'
  end

  if bcode == 0
    str << 'm'
    return str
  end

  str << ';'

  case bcode
  when 0
    str << ''
  when BC_BLACK
    str << '40'
  when BC_RED
    str << '41'
  when BC_GREEN
    str << '42'
  when BC_YELLOW
    str << '43'
  when BC_BLUE
    str << '44'
  when BC_MAGENTA
    str << '45'
  when BC_CYAN
    str << '46'
  when BC_WHITE
    str << '47'
  end

  str << 'm'

  return str
end

# Prints messages with specified format
# msg::
#  The message that we want to get printed
# tc::
#  The message text color
# bc::
#  The message text background color
# bold::
#  Whether we want the text bold or not
# underline::
#  Whether we want the text underlined or not
def sysout(msg, tc=0, bc=0, bold=0, underline=0)
  if tc != 0 or bc != 0
    msg = colorize(tc, bc) + msg
  end
  if bold != 0
    msg = boldnize(1) + msg
  end
  if underline != 0
    msg = underlinenize(1) + msg
  end

  msg = msg + resetformat

  puts msg
end

# Print system error messages
def syserr(msg)
  sysout("E: #{msg}", TC_RED, BC_BLUE)
end

# Print system informational messages
def sysinfo(msg)
  sysout("I: #{msg}", TC_WHITE, BC_BLUE)
end

# Print system verbose messages
def sysprint(msg)
  sysout("=> #{msg}", TC_GREEN, BC_BLUE)
end

# Print shell commands
def syscmd(msg)
  sysout(msg, TC_WHITE, BC_RED, 1)
end

# Execute system commands
def sysexec(cmd)
  syscmd cmd

  sysout("(SHELL OUTPUT BEGIN)", TC_MAGENTA, BC_BLUE)
  result = system(cmd)
  sysout("(SHELL OUTPUT END)", TC_MAGENTA, BC_BLUE)

  result
end

# Generates an all no package configuration
def all_no_packages
  project = Hash.new

  project['name'] = 'default'

  Dir::foreach(BSYS_ROOTDIR + "/pkg/") do |pkg|
    next if pkg == '.' or pkg == '..'

    pkg = File::basename(pkg, '.yml')

    project[pkg] = false
  end

  File::open(BSYS_DEFAULT_PROJECT, 'w') do |fs|
    fs.write(project.to_yaml)
  end
end

# Generates an all yes package configuration
def all_yes_packages
  project = Hash.new

  project['name'] = 'default'

  Dir::foreach(BSYS_ROOTDIR + "/pkg/") do |pkg|
    next if pkg == '.' or pkg == '..'

    pkg = File::basename(pkg, '.yml')

    project[pkg] = true
  end

  File::open(BSYS_DEFAULT_PROJECT, 'w') do |fs|
    fs.write(project.to_yaml)
  end
end

# Loads a single package from file and create object
def load_pkg(name)
  npkg = Package.new("#{name}.yml")

  $pkglist[npkg.getname] = npkg

  npkg.generate_targets
end

# Loads all packages from 'pkg/' directory
def load_all_pkg
  Dir::foreach(BSYS_ROOTDIR + '/pkg/') do |pkg|
    next if pkg == '.' or pkg == '..'

    load_pkg(File::basename(pkg, '.yml'))
  end
end

# Creates the default directories for the root folder
def create_rootdir
  return if File::exists? $project_rootdir

  rootdirs_list = File::join(BSYS_ROOTDIR, 'bsys/rootdirs.lst')

  f = File::open(rootdirs_list)
  unless f
    syserr "Failed to load root directory schematics list: #{rootdirs_list}"
    raise
  end

  f.each_line do |directory|
    # Remove formaters
    directory = directory.gsub(/(\r|\n)*/, '')

    FileUtils::mkdir_p(File::join $project_rootdir, directory)
  end
end
