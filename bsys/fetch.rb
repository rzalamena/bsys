require_relative 'util'

# Function called by curl fetch method that extract packages from
# containers.
#
# = Supported containers
#
# * Gunzip (tar.gz or .tgz)
# * Bunzip (tar.bz2 or .tbz)
# * Zip (.zip)
# * RAR (.rar)
def package_extract(file, target)
  sysprint "Extracting #{file} to #{target}"

  unless File::exists? target
    FileUtils::mkdir_p(target)
  end

  extract_cmd = 'tar '
  is_tarball = 1
  case file
  when /\.tar\.gz$/, /\.tgz$/
    extract_cmd << 'xvzf'
  when /\.tar\.bz2$/, /\.tbz$/
    extract_cmd << 'xvjf'
  when /\.tar.xz$/, /\.txz$/
    extract_cmd << '--xz -xvf'
  else
    is_tarball = 0
  end

  if is_tarball == 0
    case file
    when /\.zip$/
      extract_cmd = 'unzip'
    when /\.rar$/
      extract_cmd = 'unrar'
    else
      syserr "Unsupported archive format"
      raise
    end
  end

  extract_cmd << ' ' + file

  FileUtils::cd(target + '/../') do
    sysexec(extract_cmd)
  end
end

# Downloads package from URL using:
# +url+:: The download source in the format 'type://URI/path'
# +target+:: The download destination
# +param+:: Aditional parameters for cURL
def curl_fetch(url, target, param='')
  file_dist = File::join(DISTFILES, File::basename(url))

  unless File::exists? DISTFILES
    FileUtils::mkdir_p(DISTFILES)
  end

  if File::exists? file_dist
    sysprint "Package file #{file_dist} already exists"
    package_extract(file_dist, target)
    return
  end

  result = 0
  unless sysexec("curl -# -L #{param} \"#{url}\" -o \"#{file_dist}\"")
    syserr "cURL failed"
    raise
  end

  package_extract(file_dist, target)
end

# Clone a git repository
def git_clone(url, target)
  cmd = "git clone ${url} #{target}"

  protocol = ''
  protocols = url.split(':')[0]
  unless protocols.match(/\+/)
    raise 'Invalid URL protocol format #{protocols}'
  end

  protocols.split('+').each do |proto|
    next if proto == 'git'
    protocol = proto
  end

  raise 'Empty protocol' if protocol.length == 0
  case protocol
  when /http/i, /ftp/i, /https/i, /ssh/i
  else
    raise "Unsupported protocol #{protocol}"
  end

  if sysexec(cmd)
    syserr 'git failed'
    raise
  end
end

# Fetch git updates from remote repository
def git_update(target)
  cmd = "git fetch"

  FileUtils.cd(target) do
    sysexec(cmd)
  end
end
