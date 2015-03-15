module Wix


class Config < Sequel::Model
  set_primary_key :id
end

class File < Sequel::Model
  set_primary_key :id
end


$config = Wix::Config.last
fail "Config not found" unless $config

end
