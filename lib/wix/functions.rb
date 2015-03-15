
def create path, options
  wix_file = File.join(path, WIX_FILENAME)
  File.rm_f(wix_file)
  Sequel.connect("sqlite://#{wix_file}")
  require 'tables.rb'
  Wix::Config.create(
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
    created_at:   Sequel.datetime_class.now
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
      require 'models.rb'
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
