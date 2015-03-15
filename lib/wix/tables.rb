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
  Time        :removed_at   , null: false
end 

$db.create_table?  :files do
  String      :path         , null: false   , text: true  , primary_key: true
  Time        :mtime        , null: false
  Time        :ctime        , null: false
  Integer     :size
  String      :sha2_512     , null: false   , text: false , fixed: true , size: 128
end
