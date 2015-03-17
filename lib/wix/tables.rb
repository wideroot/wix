def init_tables


$db.create_table?  :pushes do
  Integer     :pushed_commit_id  , null: false , primary: true
end

$db.create_table?  :configs do
  primary_key :id
  String      :name         , null: false   , text: false
  String      :username     , null: false   , text: false
  TrueClass   :anon         , null: false
  TrueClass   :hidden       , null: false
  TrueClass   :filename     , null: false
  TrueClass   :path         , null: false
  TrueClass   :file_time    , null: false
  TrueClass   :push_time    , null: false
  TrueClass   :commit_time  , null: false
  TrueClass   :message      , null: false
  Time        :created_at   , null: false
  Time        :updated_at   , null: false
  Time        :removed_at   , null: true
end 

# the last commit are stage..
$db.create_table?  :commits do
  primary_key :id
  foreign_key :config_id    , :configs      , key: :id
  Time        :commited_at  , null: true
  String      :message      , null: true    , text: true
end

$db.create_table?  :objects do
  primary_key :id
  foreign_key :commit_id    , :commits      , key: :id
  String      :path         , null: false   , text: true
  Integer     :mtime_s      , null: false
  Integer     :mtime_n      , null: false
  Integer     :ctime_s      , null: false
  Integer     :ctime_n      , null: false
  Integer     :size
  String      :sha2_512     , null: false   , text: false , fixed: true , size: 128
  TrueClass   :added        , null: false
  TrueClass   :removed      , null: false
  # \invariant:
  # for each path, commit_id there's one or none row with removed == false
  # (and if exists id > id of the other rows with the same path, commit_id)
end


end
