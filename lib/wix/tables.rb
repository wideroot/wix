def init_tables
  puts "init tables..."

$db.create_table?  :configs do
  primary_key :id
  String      :name         , null: false   , text: false
  String      :username     , null: false   , text: false
  TrueClass   :anon         , null: false
  TrueClass   :hidden       , null: false
  TrueClass   :filename     , null: false
  TrueClass   :path         , null: false
  TrueClass   :push_time    , null: false
  TrueClass   :commit_time  , null: false
  TrueClass   :message      , null: false
  TrueClass   :file_time    , null: false
  Time        :created_at   , null: false
  Time        :updated_at   , null: false
  Time        :removed_at   , null: true
end 

$db.create_table?  :commit do
  primary_key :id
  foreign_key :config_id
end

$db.create_table?  :files do
  String      :path         , null: false   , text: true  , primary_key: true
  Time        :mtime        , null: false
  Time        :ctime        , null: false
  Integer     :size
  String      :sha2_512     , null: false   , text: false , fixed: true , size: 128
end

$db.create_table?  :objects do
  primary_key :id
  foreign_key :commit_id
  String      :path         , null: false   , text: true
  String      :name         , null: false   , text: true
  Time        :mtime        , null: false
  Integer     :size
  String      :sha2_512     , null: false   , text: false , fixed: true , size: 128
end

true
end
