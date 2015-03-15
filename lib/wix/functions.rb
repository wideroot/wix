
def create path, options
  wix_file = File.join(path, WIX_FILENAME)
  FileUtils.rm_f(wix_file)
  $db = Sequel.connect("sqlite://#{wix_file}")
  require_relative './tables.rb'
  time = Sequel.datetime_class.now
  $db[:configs].insert(
    id:           0,
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
  $wix_root = path
end

def init_wix path
  Pathname.new(path).ascend do |path|
    begin
      wix_file = File.join(path, WIX_FILENAME)
      $db = Sequel.connect("sqlite://#{wix_file}")
      next unless $db
      if $verbose_level > 0
        $db.logger = Logger.new($stderr)
        $db.sql_log_level = :debug
      end
      require_relative './models.rb'
      $wix_root = path
      return true
    rescue => ex
    end
  end
  false
end

def add path, options
end

def rm path
end
