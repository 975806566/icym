-define(IM_POOL, im_db).
-define(record_field(Table), record_info(fields, Table)).


-record(mysql_business, {
  business_id     :: integer(),
  appkey          :: string() | binary(),
  business_name   :: string() | binary(),
  admin           :: string() | binary(),
  password        :: string() | binary(),
  secretkey       :: string() | binary(),
  createtime      :: string() | binary(),
  email    = ""   :: string() | binary(),
  phone    = ""   :: string() | binary(),
  qq       = ""   :: string() | binary(),
  nickname = ""   :: string() | binary(),
  address  = ""   :: string() | binary()
}).


-record(mysql_friendlist, {
    friendlist_id,
    user_id,
    friend_id
    }).

-record(mysql_group, {
    group_id,
    topic,
    group_name,
    createtime,
    create_id
    }).