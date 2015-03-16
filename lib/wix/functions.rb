def set_wix_root path
  $wix_root = File.absolute_path(path)
end

def create_wix path, options
  wix_file = File.join(path, WIX_FILENAME)
  FileUtils.rm_f(wix_file)
  $db = Sequel.connect("sqlite://#{wix_file}")
  init_tables
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
    # insert the commit we will use as staged commit
    $db[:commits].insert(config_id: config_id)
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


def add_not_staged files
end
def add_untracked files

end
def add from, base, stage, options
  staged = {}
  not_staged = {}
  untracked = {}
  is_a_file = status(from, base, staged_objects, staged, not_staged, untracked)

  if options['no-all']
    not_saged.select! { |path, action| v != 'r' }
  end
  if options['update']
    add_not_staged(not_staged)
  elsif options['all']
    add_not_staged(not_staged)
    add_untracked(untracked)
  end
end

=begin

  if File.file?(path)
    add_file(file)
  else
    # assume dir
    if options['all']
      Dir["#{from}/**/*"].select { |path| File.file?(path) }.each do |file|
        # calculated path
        add_file(path)
      end
    elsif
      staged_objects = Wix::Object
          .select(:path)
          .where("commit_id IN (?, ?) AND path LIKE CONCAT(?, '%')",
                  stage.id, last_commit.id, from)
          .order_by(:path).all (ORDER_BY 'path', 'commit' DESC
      last_path = nil
      staged_object.each do |object|
        next if last_path == object.path
        add_file(path, object)
        last_path = object.path
      end
    end
  end
=end
end

def rm path
end

def status from, base, stage, staged, not_staged, untracked
  from = from.to_s
  staged_objects = Wix::Object
      .select(:path, :mtime, :ctime, :size, :added, :removed)
      .where("commit_id = ? AND path LIKE CONCAT(?, '%')", stage.id, from)
      .order_by(:path).all
  if File.file?(from)
    status_file(from, base, staged_objects, staged, not_staged, untracked)
    true
  else
    status_dir(from, base, staged_objects, staged, not_staged, untracked)
    false
  end
end

def status_file file, base, staged_objects, staged, not_staged, untracked
  path = Pathname.new(File.absolute_path(file)).relative_path_from(base).to_s
  file_stat = File.stat(file)
  return unless file_stat.file?
  object = staged_objects.bsearch { |object| object.path >= path }
  if object && object.path == path
    # not we could have added a previous version of a file...
    if object.added
      staged[path] = 'a'
    end
    if  stat.mtime == object.mtime &&
        stat.ctime == object.ctime &&
        stat.size == object.size
      if object.removed
        staged[path] = 'r'
      end
    else
      # modified
      # (it could be that actually it is not since we do not check hashes)
      not_staged[path] = 'm'
    end
    object.mtime = nil  # we mark this object as seen
  else
    # untracked
    untracked[path] = true
  end
  # all non seen objects are deleted not staged for commit
  staged_objects.select { |object| !object.mtime }.each do |object|
    not_staged[object.path] = 'r'
  end
end

def status_dir from, base, staged_objects, staged, not_staged, untracked
  Dir["#{from}/**/*"].select { |path| File.file?(path) }.each do |file|
    status_file(file, base, staged_objects, staged, not_staged, untracked)
  end
end

def stage_commit
  Wix::Commit.last
end
