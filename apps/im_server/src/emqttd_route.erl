%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd route message.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module (emqttd_route).

-export ([
            route/6, 
            dispatch/7,
            check_user_online/1,
            do_route_to_uid/5,
            route_online_uid/4
         ]).

-include("emqttd.hrl").

-include("mysql.hrl").

-include("emqttd_packet.hrl").

route(Packet, Topic, Payload, FromUserName, SendFun, SelfPid ) ->
    Header = Packet#mqtt_packet.header,
    Variable = Packet#mqtt_packet.variable,
    PacketId = Variable#mqtt_packet_publish.packet_id,
    Qos = Header#mqtt_packet_header.qos,
    util:print("[route_msg] => [From:~p,Con:~p,Topic:~p,PacketId:~p,Qos:~p]~n",[FromUserName, Payload, Topic, PacketId, Qos]),
    case string:tokens(binary_to_list(Topic), "@") of
        
        % ------------------------------------------------------------------------------
        % 获取服务器时间
        % ------------------------------------------------------------------------------
        [?GET_SERVER_TIME, _] ->
            Topic2 = list_to_binary(?SERVER_TIME_TOPIC),
            do_send_self(Topic2, list_to_binary(emqttd_tools:get_unixtime()), SendFun);
        
        % ------------------------------------------------------------------------------
        % 获取用户状态
        % ------------------------------------------------------------------------------
        [?GET_STATUS, Username] ->
            NewPayload = case emqttd_cm:get_state_for_nodes(list_to_binary(Username)) of
                true ->
                    Rec = <<"1&">>,
                    <<Rec/binary, Payload/binary>>;
                false ->
                    Rec = <<"0&">>,
                    <<Rec/binary, Payload/binary>>
            end,
            do_send_self(Topic, NewPayload, SendFun);
        
        % -----------------------------------------------------------------------------
        % 点对点消息。
        % -----------------------------------------------------------------------------
        [?SEND_CHAT, Username] ->
            do_route_to_uid(Qos, Payload, chat, list_to_binary(Username), FromUserName );

        % -----------------------------------------------------------------------------
        % extra 协议
        % -----------------------------------------------------------------------------
        [?SEND_EXTRA, Username] ->
            do_route_send_chat_ex( Qos, Username, Payload, FromUserName );

        % -----------------------------------------------------------------------------
        % 发送文件
        % -----------------------------------------------------------------------------
        [?SEND_FILE, Username] ->
            do_route_to_uid(Qos, Payload, sfile, list_to_binary( Username ), FromUserName);
        
        % -----------------------------------------------------------------------------       
        % 发送群文件主题
        % -----------------------------------------------------------------------------
        [?SEND_GROUP_FILE, Gid] ->
            TopicNew = <<?SEND_GROUP_FILE, "@", FromUserName/binary >>,
            NewPacket = emqttd_message:unset_flag(emqttd_message:from_packet(Packet)),
            emqttd_pubsub:route_to_groups(TopicNew, list_to_binary(Gid), NewPacket, FromUserName );

        % -----------------------------------------------------------------------------
        % 视频通讯,群通讯
        % -----------------------------------------------------------------------------
        [?SEND_VIDEO, "room"] ->
            PayloadJson = jsx:decode(Payload),
            UserList = get_value(<<"userlist">>, PayloadJson),
            case length(UserList) > ?ROOM_SIZE of
                true  ->
                    do_send_self(Topic, jsx:encode([{<<"type">>, <<"limit">>}, {<<"cause">>, <<"Room personnel quantity limitation">>}]), SendFun);
                false ->
                    {OffLineList, OnLineList} = lists:foldl(
                        fun(UserId, {AccIn1, AccIn2}) -> 
                            case emqttd_cm:lookup(UserId) of
                                undefined -> {AccIn1++[UserId], AccIn2};
                                _         -> {AccIn1, AccIn2++[UserId]}
                            end
                        end,{[], []}, UserList),
                    case length(OffLineList) =:= length(UserList) of
                        true ->
                            OffLineListString = format_user_list(UserList),
                            do_send_self(Topic, jsx:encode([{<<"type">>, <<"offline">>}, {<<"cause">>, list_to_binary(OffLineListString)}]), SendFun);
                        false ->
                            case length(OffLineList) =:= 0 of
                                true -> ok;
                                false ->
                                    OffLineListString = format_user_list(OffLineList),
                                    do_send_self(Topic, jsx:encode([{<<"type">>, <<"offline">>}, {<<"cause">>, list_to_binary(OffLineListString)}]), SendFun)
                            end,
                            _NewGroupMsgId = off_msg_id_svc:get_msg_id(),
                            % @todo cast to off_msg_svc
                            lists:foreach(
                                fun(Username1) -> 
                                    PacketId = Variable#mqtt_packet_publish.packet_id,
                                    do_route_to_uid(Qos, Payload, svideo, list_to_binary( Username1 ), FromUserName)
                                end, OnLineList)
                    end
            end;

        % -----------------------------------------------------------------------------
        % 视频通讯，给单个用户发送
        % -----------------------------------------------------------------------------
        [?SEND_VIDEO, Username] ->
            do_check_svideo_should_reply( Username, SendFun ),
            do_route_to_uid(Qos, Payload, svideo, list_to_binary( Username ), FromUserName);

        % -----------------------------------------------------------------------------
        % 可扩展参数的点对点消息
        % -----------------------------------------------------------------------------
        [?SEND_CHAT_EX, UserName] ->
            do_route_send_chat_ex(Qos, UserName, Payload, FromUserName);

        % ----------------------------------------------------------------------------
        % 获取离线消息
        % ----------------------------------------------------------------------------
        [?GET_OFF_LINE_MSG, _MsgLimit] ->
            case get( clean_sess ) of
                true ->

                    AWaitAckList = emqttd_am:load( FromUserName ),
                    emqttd_client_tools:send_no_ack_msgs( FromUserName, SelfPid, AWaitAckList ),
                    off_msg_api:get_off_msg_event( node(), FromUserName, 100000 );
                _DontSendOffMsg ->
                    skip
            end;

        % ----------------------------------------------------------------------------
        % 状态订阅
        % ----------------------------------------------------------------------------
        [ ?STATE_SUB, Username ] ->
            Username1 = list_to_binary( Username ),
            util:print("[sub_topic] => [From:~p, To:~p]~n",[ FromUserName, Username1 ]),
            %-% 自己不能订阅自己
            case Username1 of
                FromUserName ->
                    lager:error( "can't sub self ~p ~n", [ Username1 ] );

                %-% 订阅的用户不存在
                _NotTheSame ->
                    case mnesia:dirty_read( user_info, Username1 ) of
                        [ ] ->  
                            lager:error( "Username:~p not exist~n", [ Username ] );
                        [ UserInfo1 ] ->
                            OldMap = UserInfo1#user_info.apply_time,
                            case erlang:is_map( OldMap ) of
                                true ->
                                    OldList = maps:get( sub_state_list, OldMap, [] ),
                                    NewList = 
                                        case lists:member( FromUserName, OldList ) of
                                            true ->
                                                OldList;
                                            _NotContain ->
                                                [ FromUserName | OldList]
                                        end,
                                    mnesia:dirty_write( user_info, UserInfo1#user_info{ apply_time = OldMap#{ sub_state_list => NewList }} );
                                _NotMap ->
                                    mnesia:dirty_write( user_info, UserInfo1#user_info{ apply_time = #{sub_state_list => [ FromUserName ]}} )
                            end
                    end
            end;
        
        % ----------------------------------------------------------------------------
        % 状态取消订阅
        % ----------------------------------------------------------------------------
        [ ?STATE_UNSUB, Username ] ->
            case mnesia:dirty_read( user_info, list_to_binary( Username ) ) of
                [] ->
                    lager:error("UNSUB UserId not exists ~p ~n", [ Username ]);
                [ UserInfo1 ] ->
                    util:print("[unsub_topic] => [From:~p,To:~p]~n",[ FromUserName, list_to_binary( Username ) ]),
                    % 兼容以前的版本， 如果 apply_time 不是 map 类型，那么认为是旧版本不做处理
                    OldMap = UserInfo1#user_info.apply_time,
                    case erlang:is_map( OldMap ) of
                        true ->
                            OldList = maps:get( sub_state_list, OldMap, [] ),
                            NewList = lists:delete( FromUserName, OldList ),
                            mnesia:dirty_write( user_info, UserInfo1#user_info{ apply_time = OldMap#{ sub_state_list => NewList }} );
                        _NotMap ->
                            skip
                    end
            end;

        % ----------------------------------------------------------------------------
        % IOS增加推送绑定
        % ----------------------------------------------------------------------------
        [?BINDING, Token] ->
            [UserInfo] = mnesia:dirty_read(user_info, FromUserName),
            PlatformType = UserInfo#user_info.platform_type,
            case PlatformType =:= ?I_SDK of
                true ->
                    mnesia_tools:dirty_write(user_info, UserInfo#user_info{ios_token = Token});
                false -> ok
            end;

        % ---------------------------------------------------------------------------
        % IOS解除推送绑定
        % ---------------------------------------------------------------------------
        [?UN_BINDING, _] ->
            [UserInfo] = mnesia:dirty_read(user_info, FromUserName),
            PlatformType = UserInfo#user_info.platform_type,
            IosToken = UserInfo#user_info.ios_token,
            case (PlatformType =:= ?I_SDK) andalso (IosToken =/= undefined) of
                true ->
                    mnesia_tools:dirty_write(user_info, UserInfo#user_info{ios_token = undefined});
                false -> ok
            end;

        % ---------------------------------------------------------------------------
        % 识别不了的消息当作群消息处理。这是个问题
        % ---------------------------------------------------------------------------
        _ ->
            NewPacket = emqttd_message:unset_flag(emqttd_message:from_packet(Packet)),
            emqttd_pubsub:publish(NewPacket, FromUserName),
            emqttd_client_tools:msg_info(FromUserName, Topic, Payload, publish)
    end.

% -----------------------------------------------------------------------------------------------------------
% @doc 如果是点对点的视频， 那么接收者不在线的时候。 应该告诉发送者应当终止。
% @todo 待实现
% -----------------------------------------------------------------------------------------------------------
do_check_svideo_should_reply( Username, SendFun ) ->
    case emqttd_cm:get_state_for_nodes(list_to_binary(Username)) of
                true ->
                    skip;
                false ->
                    Topic = list_to_binary("svideo@" ++ binary_to_list(Username)),
                    Content = jsx:encode([{<<"type">>, <<"bye">>}, {<<"cause">>, <<"offline">>}]),
                    do_send_self( Topic, Content, SendFun )
    end.

% -----------------------------------------------------------------------------------------------------------
% 用于路由 chat_ex 消息
% -----------------------------------------------------------------------------------------------------------
do_route_send_chat_ex(Qos, ToUName, Payload, FromUserName) ->

    % -----------------------------------------------------------------
    % 获取内容和 nickname.   nickname 用于apns推送。别的地方不需要
    % -----------------------------------------------------------------
    
    PayloadList = jsx:decode( Payload ),
    NickName = proplists:get_value( <<"nickname">>, PayloadList ),
    Content = proplists:get_value( <<"content">>, PayloadList ),

    put('$emqttd_nickname', NickName),
    put('$emqttd_content',  Content),
    do_route_to_uid(Qos, Payload, chat_ex, list_to_binary(ToUName), FromUserName).

% -----------------------------------------------------------------------------------------------------------
% @doc 消息申请让别的节点来处理
% -----------------------------------------------------------------------------------------------------------
dispatch( FromUserName, Uid, Topic, Type, Qos, Content, NewMsgId) ->
    case emqttd_cm:lookup( Uid ) of
        undefined ->
            [UserInfo] = mnesia:dirty_read(user_info, Uid),
            [User] = mnesia:dirty_read( users, Uid ),
            do_save_offline_msg_zl( Topic, FromUserName, Uid, Content, Qos, UserInfo, User, Type, NewMsgId);
        Pid ->
            do_route_online_pid( Pid, Uid, Qos, Topic, Content )
    end.    


% -----------------------------------------------------------------------------------------------------------------
%  给自己回消息
% -----------------------------------------------------------------------------------------------------------------
do_send_self(Topic, Payload, SendFun) ->
    NewPacket = ?PUBLISH_PACKET(?QOS_0, Topic, undefined, Payload),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data).

% ----------------------------------------------------------------------------------------------------------------
% 发送给 ham 的消息要特殊处理。
% ham 只接收chat_ex, chat, sfile
% chat_ex   --> type = 1
% chat      --> type = 1
% sfile     --> type = 2
% ----------------------------------------------------------------------------------------------------------------
do_route_ham( UserInfo, FromUserName, Uid, Type, Content, Qos) ->
    case Type of
        sfile -> 
            emqttd_ham:send_msg_ham(UserInfo#user_info.appkey, FromUserName, Uid, 2, Content, Qos);
        chat ->
            emqttd_ham:send_msg_ham(UserInfo#user_info.appkey, FromUserName, Uid, 1, Content, Qos);
        chat_ex ->
            emqttd_ham:send_msg_ham(UserInfo#user_info.appkey, FromUserName, Uid, 1, Content, Qos);
        _OthersType ->
            lager:error("SDK type is 8 not send other message")
    end.

% -------------------------------------------------------------------------------------------------------------
% 判断这个用户是否在线
% -------------------------------------------------------------------------------------------------------------
check_user_online( User ) ->
    %-% 如果user上面登录的node与当前处理这条消息的node是同一个node。
    %-% 那么这个用户认为是不在线上，离线处理
    Node = User#users.node_id,
    case Node =:= node() of
        true -> 
            false;
        false ->
            %-% 如果用户登录上的node不在了，那么这个用户被认为不在线上
            case ets:lookup(kv, { im, Node }) of
                [] ->
                    false;
                _Found ->
                    Node
            end
    end.
    
% ----------------------------------------------------------------------------------------------------------------
% 给用户发送在线消息
% ----------------------------------------------------------------------------------------------------------------
route_online_uid( Uid, Qos, Topic, Content ) ->
    case emqttd_cm:lookup( Uid ) of
        undefined ->
            lager:error(" route online error , no this uid ~p ~n",[ Uid ]);
        Pid ->
            do_route_online_pid( Pid, Uid, Qos, Topic, Content )
    end.


% ----------------------------------------------------------------------------------------------------------------
% 用户在线，直接路由给指定用户
% ----------------------------------------------------------------------------------------------------------------
do_route_online_pid( Pid, Uid, Qos, Topic, Content ) ->
    case erlang:process_info(Pid, message_queue_len) of
        {_, Length} ->
            case Length > 1000 of
                true ->
                    ok;
                false ->
                    gen_server:cast(Pid, {send_msg, Uid, Qos, Topic, Content})
            end;
        Error ->
                lager:error("Error is message_queue_len error~p~n", [Error])
    end.
    
get_value(Key, Lists) ->
    proplists:get_value(Key, Lists).

% ---------------------------------------------------------------------------------------------------------------
%   给用户下的每一个 sdk 推送一条消息
% ---------------------------------------------------------------------------------------------------------------
-spec do_route_to_uid( Qos::integer(), Content::binary(), Type::atom(), Uid::binary(), FromUserName::binary()) -> ok.
do_route_to_uid(Qos, Content, Type, ToUid, FromUserName ) ->
    Topic = list_to_binary(lists:concat([atom_to_list(Type), "@", binary_to_list(FromUserName)])),
    emqttd_client_tools:msg_info(FromUserName, ToUid, Content, Type),
    case emqttd_cm:lookup( ToUid ) of
        undefined ->
            case mnesia:dirty_read(users, ToUid) of
                [] -> 
                    lager:error("Uid:~p not exist~n", [ ToUid ]);
                [User] ->
                    [UserInfo] = mnesia:dirty_read(user_info, ToUid),
                    
                    % ------------------------------------------------------------------------
                    % 接收者位于 ham 平台，需要特殊处理
                    % ------------------------------------------------------------------------
                    case UserInfo#user_info.id =:= <<"wx_system">> of
                        true  ->
                            do_route_ham( UserInfo, FromUserName, ToUid, Type, Content, Qos );
                        false ->
                            NewMsgId = off_msg_id_svc:get_msg_id(),
                            case check_user_online( User ) of
                                false -> 
                                    do_save_offline_msg_zl( Topic, FromUserName, ToUid, Content, Qos, UserInfo, User, Type, NewMsgId );
                                Node ->
                                    cast_svc:cast(Node#nodes.node, ?MODULE, dispatch, [FromUserName, ToUid, Topic, Type, Qos, Content, NewMsgId ])
                            end
                    end
            end;
        Pid ->
            do_route_online_pid( Pid, ToUid, Qos, Topic, Content )
    end.



% --------------------------------------------------------------------------------------------------------------
%               @doc 中流机场项目的定制化接口
% 1: 如果是点对点的svideo信息，那么不在线的时候应该给发送的人回个消息，叫他断线视频通话。
% 2: 为什么需要多此一举把apns的发送放到离线。因为外边没法获取到离线消息到底有多少条。
% --------------------------------------------------------------------------------------------------------------
do_save_offline_msg_zl( _Topic, _FromUserName, _Uid, _Content, ?QOS_0, _UserInfo, _User, _Type, _NewMsgId) ->
    skip;
do_save_offline_msg_zl( Topic, FromUserName, Uid, Content, Qos, UserInfo, User, Type, NewMsgId) ->
    off_msg_api :new_tmp_group_msg( NewMsgId, FromUserName, Topic, Content, Qos, util:longunixtime() ),
    case Type =:= svideo of
        % 视频消息不存离线
        true ->
            skip;
        _OthersOfflineMsg ->
            NowTime = util:longunixtime(),
            case (UserInfo#user_info.platform_type =:= ?I_SDK) andalso(UserInfo#user_info.ios_token =/= undefined) of
                true ->
                    % -----------------------------------------------------------------
                    % @doc 之前的设计实在是写的太烂。这段代码也只能这么处理
                    % -----------------------------------------------------------------
                    IosContent = 
                        case Type of
                            chat_ex ->
                                get('$emqttd_content');
                            _OthesrCase ->
                                Content
                        end,

                    NickName = 
                        case Type of
                            chat_ex ->
                                get('$emqttd_nickname');
                            _NotChatEx ->
                                
                                case User#users.name of
                                    undefined ->
                                    User#users.username;
                                _NotUndefined ->
                                    User#users.name
                                end
                        end,
                    off_msg_api: new_index_msg(Uid, NewMsgId, Qos, <<"p">>, {NickName, UserInfo#user_info.appkey, UserInfo#user_info.ios_token, IosContent}, NowTime );
                _NotIos ->
                    off_msg_api: new_index_msg(Uid, NewMsgId, Qos, <<"p">>, not_ios, NowTime )
            end
    end.


format_user_list(List) ->
    Rec = lists:foldl(
        fun(UId, AccIn) -> 
            [binary_to_list(UId), ","] ++ AccIn
        end, [], List),
    case length(Rec) >= 2 of
        true -> lists:concat(lists:droplast(Rec));
        false ->lists:concat(Rec)
    end.
