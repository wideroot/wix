def set_wix_root path
  $wix_root = File.absolute_path(path)
end

def create_wix path, options
  wix_file = File.join(path, WIX_FILENAME)
  FileUtils.rm_f(wix_file)
  $db = Sequel.connect("sqlite://#{wix_file}")
  puts 'wa'
  init_tables
  puts 'wa'
  time = Sequel.datetime_class.now
  $db.transaction do
    config_id = $db[:configs].insert(
      name:         options['name'],
      username:     options['user'],
      anon:         options['anon'],
      hidden:       options['hidden'],
      filename:     options['filename'],
      path:         options['path'],
      push_time:    options['push-time'],
      commit_time:  options['commit-time'],
      message:      options['message'],
      file_time:    options['file-time'],
      created_at:   time,
      updated_at:   time,
      removed_at:   nil,
    )
    $db[:commit].insert(config_id: config_id)
  end
  set_wix_root(path)
end


def init_wix! path
  if !init_wix(path)
    fail "Not a sub local index (or any of the parent directories)"
  end
end

def init_wix path
  Pathname.new(path).ascend do |path|
    wix_file = File.join(path, WIX_FILENAME)
    next unless File.file?(wix_file)
    $db = Sequel.connect("sqlite://#{wix_file}")
    if $verbose_level > 0
      $db.logger = Logger.new($stderr)
      $db.sql_log_level = :debug
    end
    require_relative './models.rb'
    set_wix_root(path)
    if !$db.table_exists?(:configs)
      fail "Invalid db `#{wix_file}': configs table does not exist"
    end
    return true
  end
  false
end


def add path, options
end

def rm path
end

def status pathname, basename, commit
  untracked = []
  added = []
  Dir["#{pathname.to_s}/**/*"].select { |path| File.file?(path) }.each do |file|
    path = Pathname.new(File.absolute_path(file)).relative_path_from(base).to_s
    file_stat = File.stat(file)
    entry = Wix::Object.select(:mtime, :ctime, :size, :added)
      .where(path: path, commit_id: commit.id)
    if entry
      if  stat.mtime == entry.mtime &&
          stat.ctime == entry.ctime &&
          stat.size == entry.size
        # tracked (and not modified) or added
        added << path if entry.added
      else
        # maybe modified
        untracked << path
      end
    else
      # untracked
      untracked << path
    end
  end
  [added, untracked]
end

def last_commit
  Wix::Commit.last
end
