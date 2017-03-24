-module (data_migration).

-export ([merge_mnesia/0, list_mnesia/0, update_users/0, uid_load/1]).

-include("mysql.hrl").

-include("emqttd.hrl").

-include_lib("stdlib/include/qlc.hrl").

merge_mnesia() ->
    merge_business(),
    merge_firend_list(),
    merge_group().

list_mnesia() ->
    {length(list_business()), length(list_firend_list()), length(list_group())}.
    
merge_business() ->
    MatchHead = #business{appkey_id='$1',  _='_'},
    Guard = {'>', '$1', 0},
    List = mnesia:dirty_select(business, [{MatchHead, [Guard], ['$_']}]),
    lists:foreach(fun(Business) ->
        Record = #mysql_business{
            business_id   = Business#business.appkey_id,
            appkey        = Business#business.appkey,
            business_name = Business#business.name,
            admin         = Business#business.admin,
            password      = Business#business.password,
            secretkey     = Business#business.secure,
            createtime    = 'now()'
        },
        mysql_utils:insert(?IM_POOL, business, Record, ?record_field(mysql_business))
    end, List).

merge_firend_list() ->
    MatchHead = #firend_list{id='$1',  _='_'},
    Guard = {'>', '$1', 0},
    List = mnesia:dirty_select(firend_list, [{MatchHead, [Guard], ['$_']}]),
    lists:foreach(fun(FirendList) ->
        Record = #mysql_friendlist{
            friendlist_id = FirendList#firend_list.id,
            user_id       = FirendList#firend_list.user_id,
            friend_id     = FirendList#firend_list.firend_id},
        mysql_utils:insert(?IM_POOL, friendlist, Record, ?record_field(mysql_friendlist))
    end, List).    

merge_group() ->
    MatchHead = #group{id='$1',  _='_'},
    Guard = {'>', '$1', 0},
    List = mnesia:dirty_select(group, [{MatchHead, [Guard], ['$_']}]),
    lists:foreach(fun(Group) ->
        Record = #mysql_group{
            group_id   = Group#group.id,
            topic      = Group#group.topic,
            group_name = Group#group.name,
            createtime = 'now()',
            create_id  = Group#group.create_id},
        mysql_utils:insert(?IM_POOL, group, Record, ?record_field(mysql_group))
    end, List).

list_business() ->
    MatchHead = #business{appkey_id='$1',  _='_'},
    Guard = {'>', '$1', 0},
    mnesia:dirty_select(business, [{MatchHead, [Guard], ['$_']}]).

list_firend_list() ->
    MatchHead = #firend_list{id='$1',  _='_'},
    Guard = {'>', '$1', 0},
    mnesia:dirty_select(firend_list, [{MatchHead, [Guard], ['$_']}]).  

list_group() ->
    MatchHead = #group{id='$1',  _='_'},
    Guard = {'>', '$1', 0},
    L = mnesia:dirty_select(group, [{MatchHead, [Guard], ['$_']}]),
    lists:foreach(fun(I) -> 
        io:format("~p~n",[I])
    end, lists:sort(L)),
    L.

update_users() ->
    List = mnesia:dirty_match_object(user_info, #user_info{status = 1 , _ ='_'}),
    lists:foreach(fun(UserInfo) ->
        mnesia_tools:dirty_write(user_info, UserInfo#user_info{status = 0})
    end, List).

uid_load(Appkey) when is_binary(Appkey)->
    F = fun() ->
           qlc:e(qlc:q([X || X <- mnesia:table(user_info),X#user_info.appkey =:= Appkey]))
        end,
    {atomic,UserInfolist} = mnesia:transaction(F),
    Uidlist = [UserInfo#user_info.id || UserInfo <- UserInfolist],
    Uidlist2 = split_uid_list(Uidlist, []),
    lists:foldl(
        fun(Uids, Acc)->
            Name = lists:concat(["uid_data", Acc]),
            {ok,Pid} =  file:open(lists:concat(["/opt/etcloud/im_server/uid_data/", Name,".erl"]),[append]),
            Name2 = lists:concat(["-module(" ,Name, ").\n"]),
            file:write(Pid,Name2),
            file:write(Pid,"-export ([load/1]).\n"),
            lists:foldl(
                fun(Uid, Acc1)->
                    file:write(Pid,"load("++integer_to_list(Acc1)++") ->\n"),
                    file:write(Pid,"\t<<\""++binary_to_list(Uid)++"\">>;\n"),
                    Acc1+1
                end,1, Uids),
            file:write(Pid,"load(_) -> \n"),
            file:write(Pid,"undefined . \n"),
            file:close(Pid),
            Acc+1
        end,1, Uidlist2).

split_uid_list(UidList, Acc) when length(UidList) > 10000 ->
    {Head, Tail} = lists:split(10000, UidList),
    NewAcc = Acc ++ [Head],
    split_uid_list(Tail, NewAcc);

split_uid_list(UidList, Acc)->
    Acc ++ [UidList].
