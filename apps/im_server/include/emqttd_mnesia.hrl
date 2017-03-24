-define(RAM,      {ram_copies,  [node()]}).
-define(DISC,     {disc_copies, [node()]}).

%% table宏定义
-define(
   TABLE_DEF(Name, Type, Copies, Fields),
   {Name, [Copies, {type, Type}, {attributes, Fields}]}).
-define(
   TABLE_DEF(Name, Type, Copies, RecordName, Fields),
   {Name, 
    [Copies, {type, Type}, {record_name, RecordName}, {attributes, Fields}]}).

-define(TABLE_DEF(Name, Type, Copies, RecordName, Fields, StorageProperties),
   {Name, [Copies, {type, Type}, {record_name, RecordName}, {attributes, Fields}, {storage_properties,  StorageProperties} ]}).

-record(user_id,    {type, counter}).
-record(appkey_id,  {type, counter}).
-record(node_id,    {type, counter}).
-record(off_msg_id, {type, counter}).
-record(group_id,   {type, counter}).    