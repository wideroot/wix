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
end


end
