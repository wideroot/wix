def create_wix path, options
  wix_file = File.join(path, WIX_FILENAME)
  FileUtils.rm_f(wix_file)
  $db = Sequel.connect("sqlite://#{wix_file}")
  puts 'wa'
  init_tables
  puts 'wa'
  time = Sequel.datetime_class.now
  puts $db[:configs].insert(
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
  $wix_root = wix_file
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
    $wix_root = wix_file
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
