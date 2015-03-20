def normalize_path_relative_to(file, base)
  relative = Pathname.new(File.absolute_path(file)).relative_path_from(base).to_s
  if relative != '.' && !relative.start_with?('./')
    relative = './' + relative
  end
  relative
end

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

def init_empty_commit config_id
  commit_id = Wix::Commit.insert(config_id: config_id)
  warn "init empty commit r#{commit_id}" if $verbose_level > 0
end

def push
  # get the commits we need to push
  pre_last_commit = Wix::Push.last
  if pre_last_commit
    next_commit_id =  pre_last_commit.pushed_commit_id + 1
    next_is_new = false
  else
    next_commit_id = 0
    next_is_new = true
  end
  commits = Wix::Commit
      .select
      .where('id >= ?', next_commit_id)
      .order_by(Sequel.asc(:id))
      .all
  commits.pop  # the last one is the staged
  if commits.empty?
    raise "Everything up-to-date"
  end

  # retrieve info we need to connect to the server
  last_commited_id = commits.last.id
  first_config = commits.first.config
  index_name = first_config.name
  index_username = first_config.username
  puts "Pushing sub local index #{index_username}/#{index_name} ..."
  print "Enter password: "
  user_password = $stdin.noecho(&:gets).chomp

  # prepare push_file
  last_config_id = nil
  config = nil
  push_file = []
  commits.each do |commit|
    index_config = nil
    if last_config_id != commit.config_id
      config = commit.config
      last_config_id = config.id
      index_config = config.generate_index_config(
          force_new: next_is_new, force_no_update: false)
    end

    objects = Wix::Object.where(commit_id: commit.id).all.map do |object|
      fail "Expected `.' got `#{path_entries.first}'" if path_entries.first != '.'
      path_entries = path_entries[1..-1]
      { size:       object.size,
        sha2_512:   object.sha2_512,
        filename:   config.filename ? path_entries.last : nil,
        resource_identifier: config.resource_identifier ? object.path : nil,
        created_at: config.file_time ? Time.at(object.mtime_s).utc.tv_sec : nil,
        removed:    config.notification ? true : object.removed,
      }
    end
    push_file << {
      rid:          commit.rid,
      message:      commit.message,
      commited_at:  config.commit_time ? commit.commited_at.tv_sec : nil,
      index_config: index_config,
      objects:      objects,
    }
    next_is_new = false
  end

  $db.transaction do
    # check nothing has been pushed
    post_last_commit = Wix::Push.last
    if post_last_commit != pre_last_commit
      raise "Transaction aborted expected last commit to be `#{pre_last_commit}', got `#{post_last_commit}'"
    end

    # connect and push...
    uri = URI("#{API_SERVER_URI}/push/#{index_name}")
    req = Net::HTTP::Post.new(uri)
    req.basic_auth index_username, user_password
    req.set_form_data(push_file: push_file.to_json) 
    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end
    if res.code != '200'
      raise "Not expected server response. Got code `#{res.code}': #{res}"
    end

    # mark the commits pushed as pushed
    Wix::Push.insert(pushed_commit_id: last_commited_id)
  end
  puts "Pushed sub local index #{index_username}/#{index_name}"
end


def commit message
  query = <<HDOC
INSERT INTO objects
  ( commit_id
  , path, mtime_s, mtime_n, ctime_s, ctime_n, size, sha2_512
  , added, removed
  )
SELECT ?, path, mtime_s, mtime_n, ctime_s, ctime_n, size, sha2_512, 0, 0
FROM objects
WHERE commit_id = ? AND removed != 1
HDOC
  now = Time.now.utc
  $db.transaction do
    commit = Wix::Commit.last
    commit.message = message
    commit.commited_at = now
    commit.save
    if !Wix::Object.where('commit_id = ? AND (removed == 1 OR added == 1)',
                           commit.id).first
      raise "nothing added to commit"
    end
    last_config = Wix::Config.select(:id).last
    new_commit_id = Wix::Commit.insert(config_id: last_config.id)
    raise "new commit id is 0" if new_commit_id == 0
    $db[query, new_commit_id, commit.id].insert
  end
end

def connect file
  $db = Sequel.connect("sqlite://#{file}")
  if $verbose_level > 0
    $db.logger = Logger.new($stderr)
    $db.sql_log_level = :debug
  end
  require_relative './models.rb'
  $db
end

def create_wix path, options
  wix_file = File.join(path, WIX_FILENAME)
  FileUtils.rm_f(wix_file)
  connect(wix_file)
  init_tables
  now = Time.now.utc
  $db.transaction do
    config_id = Wix::Config.insert(
      name:         options['name'],
      display_name:         options['display_name'],
      username:     options['user'],
      anon:         options['anon'],
      hidden:       options['hidden'],
      filename:     options['filename'],
      resource_identifier:         options['resource_identifier'],
      push_time:    options['push-time'],
      commit_time:  options['commit-time'],
      message:      options['message'],
      file_time:    options['file-time'],
      notification: options['notification'],
      created_at:   now,
      updated_at:   now,
      removed_at:   nil,
    )
    # insert the commit we will use as staged commit
    init_empty_commit(config_id)
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
    connect(wix_file)
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
      warn "add not staged 'r' object #{object}" if $verbose_level > 0
      rm_object(object)
      rm_object(last_object)
    when 'm'
      warn "add not staged 'm' object #{object}" if $verbose_level > 0
      fail "Trying to modify path `#{file}' with no last_object" unless last_object
      add_file(file, stage, last_object: last_object)
    else
      fail "Invalid action `#{action}' for staged file."
    end
    warn "removed last object #{last_object}" if $verbose_level > 0
  end
end

def add_untracked files, stage
  files.each do |file, o|
    add_file(file, stage)
  end
end

def rm_object(object)
  if object && !object.removed
    object.removed = true
    object.save
  end
end

def add_file(path, stage, last_object: nil, removed: false)
  stat = File.stat(path)
  sha2_512 = calculate_sha2_512(path)
  if last_object
    warn "insert #{path} and remove object #{last_object}" if $verbose_level > 0
    $db.transaction do
      insert_object(path, stage, stat, sha2_512, removed)
      rm_object(last_object)
    end
  else
    warn "insert #{path}" if $verbose_level > 0
    insert_object(path, stage, stat, sha2_512, removed)
  end
end

def insert_object(path, stage, stat, sha2_512, removed)
  Wix::Object.insert(
    commit_id: stage.id,
    path: path,
    mtime_s: stat.mtime.tv_sec,
    mtime_n: stat.mtime.tv_nsec,
    ctime_s: stat.ctime.tv_sec,
    ctime_n: stat.ctime.tv_nsec,
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

def rm_paths froms, base, stage, options
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

    # add staged that matched iif its action is added
    staged.each do |path, objects|
      added_objects = 0
      objects.each do |object_id, o|
        action = o[:action]
        object = o[:object]
        if action == 'a'
          objects_to_untrack.add([object, nil])
          added_objects += 1
        end
      end
      if added_objects > 1
        fail "More than one(#{added_objects}) added object for `#{path}'"
      end
    end

    not_staged.each do |path, o|
      action = o[:action]
      object = o[:object]
      last_object = o[:last_object]
      if action == 'r'
        # add not removed staged to commit
        objects_to_untrack.add([object, last_object])
      elsif options['force']
        # remove a new file if force
        objects_to_untrack.add([object, last_object])
      elsif options['notify']
        # notify a new file if force
        objects_to_notify.add(path)
      else
        # we cannot delete a file that has not been added
        fails << from
      end
    end
  end

  if !fails.empty?
    fail "the following file has local modifications:\n #{fails.to_a.join("\n")}\n(use -n to notify the file, or -f to force removal)"
  end
  if $verbose_level > 0
    warn objects_to_notify.inspect
    warn objects_to_untrack.inspect
  end
  objects_to_notify.each do |path|
    add_file(path, stage, removed: true)
  end
  objects_to_untrack.each do |object, last_object|
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
  path_prefix = normalize_path_relative_to(file, base)
  path_prefix += '/' unless is_a_file
  staged_objects = {}
      # TODO this doesn't work... ??
  Wix::Object
      .select(:id, :path, :mtime_s, :mtime_n, :ctime_s, :ctime_n, :size, :added, :removed)
      .where("commit_id = ? AND path LIKE (? || '%')", stage.id, path_prefix)
      .order_by(Sequel.asc(:path), Sequel.desc(:id))
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
    warn "staged objects: #{staged_objects}"  # TODO warn
  end

  seen = Set.new
  if is_a_file
    status_object(from, base, staged_objects, staged, not_staged, untracked, seen)
  else
    status_dir(from, base, staged_objects, staged, not_staged, untracked, seen)
  end
  # check when a file has been deleted
  staged_objects.each do |path, objects|
    object = objects[:last_object]
    if !seen.member? object
      fail "unseen filed marked as not_staged" if not_staged[path]
      not_staged[path] = {action: 'r', object: object, last_object: objects[:objects][-2]}
    end
  end

  if $verbose_level > 0
    warn "= = = = = = = = ="
    warn "- not staged (removed)"
    not_staged.each do |path, o|
      next if o[:action] != 'r'
      warn "    #{path}"
      warn "      #{o[:action]} #{o[:object] ? o[:object].id : 'nil'}"
    end
    warn ""
    warn "============== ]]"
    warn ""
  end

  is_a_file
end

def status_object file, base, staged_objects, staged, not_staged, untracked, seen
  path = normalize_path_relative_to(file, base)
  file_stat = File.stat(file)
  return unless file_stat.file?
  objects = staged_objects[path]
  new_object = true
  if objects
    objects[:objects].each do |staged_object|
      action = nil
      if staged_object.added
        action = 'a'
      end
      if staged_object.removed
        action = action ? 'n' : 'r'
      end
      if action
        # do not add non modified staged fileds
        staged[path][staged_object.id] = {action: action, object: staged_object}
      end
    end
    # we could have add/rm a previous version of file
    object = objects[:last_object]
    if  file_stat.mtime.tv_sec  == object.mtime_s &&
        file_stat.mtime.tv_nsec == object.mtime_n &&
        file_stat.ctime.tv_sec  == object.ctime_s &&
        file_stat.ctime.tv_nsec == object.ctime_n &&
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
    seen.add(object)
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
      warn "    #{path}"
      warn "!! expected true, got `#{v.inspect}'" unless v == true
    end
  end
end

def status_dir from, base, staged_objects, staged, not_staged, untracked, seen
  Dir["#{from}/**/*"].select { |path| File.file?(path) }.each do |file|
    status_object(file, base, staged_objects, staged, not_staged, untracked, seen)
  end
end

def stage_commit
  Wix::Commit.last
end
