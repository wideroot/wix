module Wix


class Push < Sequel::Model
  set_primary_key :pushed_commit_id
end

class Config < Sequel::Model
  set_primary_key :id
  def generate_index_config force_new: false, force_no_update: false
    { display_name:         display_name,
      anon:                 anon,
      hidden:               hidden,
      filename:             filename,
      resource_identifier:  resource_identifier,
      push_time:            push_time,
      commit_time:          commit_time,
      message:              message,
      file_time:            file_time,
      force_new:            force_new,
      force_no_update:      force_no_update,
    }
  end
end

class Commit < Sequel::Model
  set_primary_key :id
  many_to_one :config
  def rid  # TODO this should be the sha of the commit json object...
    Digest::SHA1.hexdigest("#{id} #{commited_at}")
  end
end

class Object < Sequel::Model
  set_primary_key :id
  def mtime
    Time.at(mtime_s)
  end
  def ctime
    Time.at(ctime_s)
  end
end


end
