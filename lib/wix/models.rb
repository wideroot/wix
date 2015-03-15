module Wix


class Config < Sequel::Model
  set_primary_key :id
end

class File < Sequel::Model
  set_primary_key :id
end


$index = Index.last
fail "Config not found" unless $index

end
