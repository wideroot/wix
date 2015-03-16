def calculate_sha2_512 file
  absolute_path = File.absolute_path(file)
  shell_path = Shellwords.escape(absolute_path)
  stdout, stderr, status = Open3.capture3("sha512sum -b #{shell_path}")
  hash = stdout.split.first
  if !status.success? || stderr != ""
    fail "sha512sum error. status: #{status}, stderr: \n#{stderr}"
  end
  return hash
end

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


def add_not_staged files, stage
  files.each do |file, o|
    action = o[:action]
    last_object = o[:last_object]
    object = o[:object]
    case action
    when 'r'
      rm_object(object)
    when 'm'
      add_file(file, stage)
    else
      fail "Invalid action `#{action}' for staged file."
    end
    rm_object(last_object)
  end
end

def add_untracked files, stage
  files.each do |file, o|
    add_file(file, stage)
  end
end

def rm_object(object)
  if !object.removed
    object.removed = true
    object.save
  end
end

def add_file(path, stage, removed = false)
  stat = File.stat(path)
  sha2_512 = calculate_sha2_512(path)
  Wix::Object.insert(
    commit_id: stage.id,
    path: path,
    mtime: stat.mtime,
    ctime: stat.ctime,
    size: stat.size,
    sha2_512: sha2_512,
    added: true,
    removed: removed,
  )
end

def add from, base, stage, options
  staged = Hash.new { |h,k| h[k] = {} }
  not_staged = {}
  untracked = {}
  is_a_file = status(from, base, stage, staged, not_staged, untracked)

  if options['no-all']
    not_staged.select! { |path, o| o[:action] != 'r' }
  end
  if options['update']
    add_not_staged(not_staged, stage)
  elsif options['all']
    add_not_staged(not_staged, stage)
    add_untracked(untracked, stage)
  end
end

def rm_files froms, base, stage, options
  objects_to_untrack = Set.new
  objects_to_notify = Set.new
  fails = Set.new
  froms.each do |from|
    staged = Hash.new { |h,k| h[k] = {} }
    not_staged = {}
    untracked = {}
    is_a_file = status(from, base, stage, staged, not_staged, untracked)
    if staged.empty? && not_staged.empty?
      fail "`#{from.to_s}' did not match any file"
    end
    staged.each do |path, objects|
      objects_to_delete.add([object[:last_object], nil])
    end
    not_staged do |path, o|
      action = o[:action]
      object = o[:object]
      last_object = o[:last_object]
      if action == 'r'
        objects_to_delete.add([object, last_object])
      elsif options['force']
        objects_to_delete.add([object, last_object])
      elsif options['notify']
        objects_to_notify.add(path)
      else
        fails << from
      end
    end
  end
  if !fails.empty?
    fail "the following file has local modifications:\n #{fails.to_a.join("\n")}\n(use -n to notify the file, or -f to force removal)"
  end
  objects_to_notify.each do |path|
    add_file(path, stage, removed: true)
  end
  objects_to_delete.each do |object, last_object|
    rm_object(object)
    rm_object(last_object) if last_object
  end
end

# \pre:
#   staged default value is {}
#   staged_objects[:last_object] is a Wix::Object
#   staged_objects[:objects] is an array of [Wix::Object]
# \post:
#   staged[path][object_id] is
#     { action: \in 'a', 'r', 'n'}, object: is a Wix::Object}
#   not_staged[path] = { action: \in {'m', 'r'}, object: is a Wix::Object}
#   untracked[path] = true
def status from, base, stage, staged, not_staged, untracked
  file = from.to_s
  is_a_file = File.file?(file)
  path_prefix = Pathname.new(File.absolute_path(file)).relative_path_from(base).to_s
  path_prefix += '/' unless is_a_file
  staged_objects = {}
      # TODO this doesn't work... ??
  Wix::Object
      .select(:id, :path, :mtime, :ctime, :size, :added, :removed)
      .where("commit_id = ? AND path LIKE (? || '%')", stage.id, path_prefix)
      .order_by(:path, Sequel.desc(:id))
      .all
  .each do |object|
    if !staged_objects[object.path]
      staged_objects[object.path] = {last_object: object, objects: []}
    end
    staged_objects[object.path][:objects] << object
  end

  if $verbose_level > 0
    warn ""
    warn ""
    warn "[[ =============="
    warn ""
    warn staged_objects  # TODO warn
  end

  if is_a_file
    status_object(from, base, staged_objects, staged, not_staged, untracked)
  else
    status_dir(from, base, staged_objects, staged, not_staged, untracked)
  end
  # check when a file has been deleted
  staged_objects.each do |path, objects|
    object = objects[:last_object]
    if object.mtime != nil
      fail "unseen filed marked as not_staged" if not_staged[path]
      not_staged[path] = {action: 'r', object: object, last_object: objects[:objects][-2]}
    end
  end

  if $verbose_level > 0
    warn "= = = = = = = = ="
    warn "- not staged (modified)"
    not_staged.each do |path, o|
      next if o[:action] != 'r'
      warn "    #{path}"
      warn "      #{o[:action]} #{o[:object] ? o[:object].id : 'nil'}"
    end
  end

  warn ""
  warn "============== ]]"
  warn ""
  is_a_file
end

def status_object file, base, staged_objects, staged, not_staged, untracked
  path = Pathname.new(File.absolute_path(file)).relative_path_from(base).to_s
  file_stat = File.stat(file)
  return unless file_stat.file?
  objects = staged_objects[path]
  new_object = true
  if objects
    objects[:objects].each do |staged_object|
      action = ''
      if staged_object.added
        action = 'a'
      end
      if staged_object.removed
        action = action == '' ? 'r' : 'n'
      end
      staged[path][staged_object.id] = {action: action, object: staged_object}
    end
    # we could have add/rm a previous version of file
    object = objects[:last_object]
    if  file_stat.mtime == object.mtime &&
        file_stat.ctime == object.ctime &&
        file_stat.size == object.size
      # path is not a new object
      # do nothing then
      new_object = false
    else
      if !object.removed
        # if not was removed then it's modified
        # (it could be that actually it is not since we do not check hashes)
        not_staged[path] = {action: 'm', last_object: object}
      else
        # otherwise it's untracked
        untracked[path] = true
      end
    end
    object.mtime = nil  # we mark this object as seen
  else
    # untracked
    untracked[path] = true
  end

  if $verbose_level > 0
    warn "================="
    warn "status from #{file} with base #{base}"
    warn "#{new_object ? "new" : "not new"} #{path}"
    warn "- staged"
    staged.each do |path, objects|
      warn "    #{path}"
      objects.each do |object_id, o|
        warn "      #{o[:action]} #{o[:object].id}"
      end
    end
    warn "- not staged (modified)"
    not_staged.each do |path, o|
      warn "    #{path}"
      warn "      #{o[:action]} #{o[:object]}"
    end
    warn "- untracked"
    untracked.each do |path, v|
      puts "    #{path}"
      warn "!! expected true, got `#{v.inspect}'" unless v == true
    end
  end
end

def status_dir from, base, staged_objects, staged, not_staged, untracked
  Dir["#{from}/**/*"].select { |path| File.file?(path) }.each do |file|
    status_object(file, base, staged_objects, staged, not_staged, untracked)
  end
end

def stage_commit
  Wix::Commit.last
end
