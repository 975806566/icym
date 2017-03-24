%%------------------------------------------------------------------------------
%%% @doc
%%% emqttd mnesia function tools.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(mnesia_tools).

-include_lib("stdlib/include/qlc.hrl").
-include("emqttd.hrl").
%% API
-export([get_node_id/0,
         get_appkey_id/1,
         get_next_user_id/0,
         get_next_appkey_id/0,
         get_next_node_id/0,
         get_next_off_msg_id/0,
         get_next_group_id/0,
         get_next_user_info_id/0,
         read/1,
         read/2,
         read_list/2,
         index_read/3,
         write/1,
         write/2,
         write_list/2,
         delete/1,
         delete/2,
         delete_list/2,
         delete_object/1,
         dirty_read/1,
         dirty_read/2,
         dirty_read_list/2,
         dirty_index_read/3,
         dirty_index_read_list/3,
         dirty_write/1,
         dirty_write/2,
         dirty_write_list/2,
         dirty_delete/1,
         dirty_delete/2,
         dirty_delete_list/2,
         dirty_delete_object/1,
         dirty_delete_object_list/1
        ]).

get_node_id() ->
    case mnesia_tools:dirty_index_read(nodes, node(), #nodes.node) of
        [] -> [];
        [#nodes{id = Id}] -> Id
    end.
get_appkey_id(Appkey) ->
    case mnesia_tools:dirty_index_read(business, Appkey, #business.appkey) of
        [] -> [];
        [#business{appkey_id = Id}] -> Id
    end.


get_next_user_id() ->
    mnesia:dirty_update_counter(user_id, user_id, 1).

get_next_appkey_id() ->
    mnesia:dirty_update_counter(appkey_id, appkey_id, 1).

get_next_node_id() ->
    mnesia:dirty_update_counter(node_id, node_id, 1).

get_next_off_msg_id() ->
    mnesia:dirty_update_counter(off_msg_id, off_msg_id, 1).

get_next_group_id() ->
    mnesia:dirty_update_counter(group_id, group_id, 1).

get_next_user_info_id() ->
    mnesia:dirty_update_counter(user_info_id, user_info_id, 1).    

%% @doc delete key
delete({Table, KeyList}) when is_list(KeyList) ->
    %% Fun = fun() ->
    %%               lists:map(fun(Key) ->
    %%                                 ok = mnesia:delete(Table, Key, write),
    %%                                 Key
    %%                         end, KeyList)
    %%       end,
    %% %% mnesia:sync_transaction(Fun);
    %% mnesia:activity(async_dirty, Fun, [], mnesia_frag);
    delete_list(Table, KeyList);
delete({Table, Key}) ->
    delete(Table, Key).

delete(Table, Key) ->
    Fun = fun() ->
        mnesia:delete(Table, Key, write),
        Key
    end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

delete_list(Table, KeyList) when is_list(KeyList) ->
    Fun = fun() ->
        lists:map(fun(Key) ->
            mnesia:delete(Table, Key, write),
            Key
        end, KeyList)
          end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

%% @doc delete_object
delete_object(Record) ->
    Fun = fun() ->
        mnesia:delete_object(Record)
    end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).


%% @doc save record
%% @spec
%% @end
write(Record) ->
    Fun = fun() ->
        mnesia:write(Record)
    end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

write(Table, Record) ->
    Fun = fun() ->
        mnesia:write(Table, Record, write)
    end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

write_list(Table, RecordList) ->
    Fun = fun() ->
        lists:map(fun(Record) ->
            mnesia:write(Table, Record, write),
            Record
        end, RecordList)
    end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

read({Table, Id}) ->
    read(Table, Id).

read(Table, Id) ->
    Fun = fun() ->
        mnesia:read(Table, Id)
    end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

read_list(Table, IdList) ->
    Fun = fun() ->
        lists:foldl(fun(Id, {SuccessRet, FailedRet}) ->
            case mnesia:read(Table, Id) of
                [] ->
                    {SuccessRet, [Id|FailedRet]};
                [R|_] ->
                    {[R|SuccessRet], FailedRet}
            end
        end, {[],[]}, IdList)
          end,
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).
                  
                  

index_read(Table, Key, KeyPos) ->
    Fun = fun() ->
        mnesia:index_read(Table, Key, KeyPos)
    end,
    %% mnesia:sync_transaction(Fun).
    mnesia:activity(sync_transaction, Fun, [], mnesia_frag).

%% @doc dirty save record for fast but no safe
%% @spec
%% @end
%% dirty_write(Record) ->
%%     mnesia:dirty_write(Record).

dirty_write(Record) ->
    Fun = fun() ->
        mnesia:write(Record, write)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_write(Table, Record) ->
    Fun = fun() ->
          mnesia:write(Table, Record, write)          
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_write_list(Table, RecordList) when is_list(RecordList) ->
    Fun = fun() ->
        lists:map(fun(Record) ->
            mnesia:write(Table, Record, write),
            Record
        end, RecordList)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_read({Table, KeyList}) when is_list(KeyList) ->
    dirty_read_list(Table, KeyList);
dirty_read({Table, Key}) ->
    dirty_read(Table, Key).

dirty_read(Table, Key) ->
    Fun = fun() -> 
      mnesia:read(Table, Key)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_read_list(Table, KeyList) when is_list(KeyList)->
    Fun = fun() ->
        lists:foldl(fun(Key, {SuccessRet, FailedRet}) -> 
            case  mnesia:dirty_read(Table, Key) of
                [] ->
                    {SuccessRet, [Key|FailedRet]};
                [R|_] ->
                    {[R|SuccessRet], FailedRet}
            end
        end, {[], []}, KeyList)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_index_read(Table, Key, KeyPos) ->
    Fun = fun() -> mnesia:dirty_index_read(Table, Key, KeyPos)
          end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_index_read_list(Table, KeyList, KeyPos) ->
    Fun = lists:foldl(fun(Key, {Success, Failed}) ->
        case  mnesia:dirty_index_read(Table, Key, KeyPos) of
            [] ->
                {Success, [Key|Failed]};
            List ->
                {List ++ Success, Failed} 
        end
    end, {[], []},KeyList),
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_delete({Table, KeyList}) when is_list(KeyList) ->
    dirty_delete_list(Table, KeyList);
dirty_delete({Table, Key}) ->
    dirty_delete(Table, Key).

dirty_delete_list(Table, KeyList) when is_list(KeyList) ->
    Fun = fun() ->
        lists:foreach(fun(Key) ->
            mnesia:delete({Table, Key})
        end, KeyList)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_delete(Table, Key) ->
    Fun = fun() -> 
        mnesia:delete({Table, Key}),
        Key
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_delete_object_list(Records) when is_list(Records) ->
    Fun = fun() ->
        lists:foreach(fun(Record) ->
            dirty_delete_object(Record)
        end, Records)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).

dirty_delete_object(Record) ->
    Fun = fun() ->
        mnesia:delete_object(Record)
    end,
    mnesia:activity(async_dirty, Fun, [], mnesia_frag).