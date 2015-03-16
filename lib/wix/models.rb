module Wix


class Config < Sequel::Model
  set_primary_key :id
end

class Commit < Sequel::Model
  set_primary_key :id
  many_to_one :config
end

class Object < Sequel::Model
  set_primary_key :id
  def unique_id_in_commit
    "#{sha2_512} #{size} #{mtime} #{ctime} #{path}"
  end
  def mtime
    Time.at(mtime_s)
  end
  def ctime
    Time.at(ctime_s)
  end
end


end
