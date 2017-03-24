-module(emqttd_client_tools).

-export([send_message/5, send_off_message/4, 
    fail_msg_to_offmsg/1, send_state_subscribe_msg/3,
    send_state_subscribe_msg1/3, notify_duplicate/3, check_packet_id/1, shutdown/5]).

-export ([notice_add_buddy/2, notice_remove_buddy/2]).

-export ([update_info/4,  terminate/4]).

-export ([handle_call/3, handle_cast/2, handle_info/2]).
-export ([msg_info/4, login_info/4, send_no_ack_msgs/3]).

-include("emqttd.hrl").

-include("emqttd_packet.hrl").

-define(LENGTH, 100).

-record(state, {connection,
                peer_name,
                conn_name,
                await_recv,
                conn_state,
                rate_limit,
                parser_fun,
                proto_state,
                packet_opts,
                keepalive,
                sendfun,
                packet_id,
                sub_list}).

%% handle_info用户登录成功后，更新用户信息
update_info( Username, PlatformType, IOSToken, Peername ) ->
    [User] = mnesia:dirty_read(users, Username),
    [UserInfo] = mnesia:dirty_read(user_info, User#users.user_id),
    case UserInfo#user_info.status =:= 1 andalso  User#users.node_id =/= mnesia_tools:get_node_id() of
        true ->
            [Node] = mnesia:dirty_read(nodes, User#users.node_id),
            cast_svc:cast(Node#nodes.node, emqttd_client_tools, notify_duplicate, [Username, node(), self()]);
        false ->
            ok
    end,
    Time = list_to_integer(emqttd_tools:get_unixtime()),
    mnesia_tools:dirty_write(users, User#users{node_id = mnesia_tools:get_node_id()}),
    UserInfo3 = UserInfo#user_info{
        platform_type = PlatformType, 
        ios_token = IOSToken, 
        status = 1, 
        last_login_time = Time,
        login_count = UserInfo#user_info.login_count + 1,
        ip = emqttd_net:format(ip, Peername)},
    UserInfo2 = case UserInfo#user_info.activation_time =:= 0 of
        true ->
            UserInfo3#user_info{activation_time = Time};
        false ->
            UserInfo3
    end,
    mnesia_tools:dirty_write(user_info, UserInfo2),
    
    %% 用户上线，通知订阅状态者
    StateSubscribeList = do_get_sub_satus_list( UserInfo3 ),

    send_state_subscribe_msg(StateSubscribeList, Username, online),
    login_info(Username, UserInfo3#user_info.ip, 1, undefined).

% ---------------------------------------------------------------
% 那些未收到 ack 的消息，全部转化为离线消息发送出去
% ---------------------------------------------------------------
send_no_ack_msgs( Username, SelfPid, AWaitAckList ) ->
    NowTime = util:longunixtime(),
    case length(AWaitAckList) > 1000 of
        true -> ok;
        false ->
            Fun = fun( Packet ) ->
                #mqtt_packet{
                    payload = Content,
                    header = Header,
                    variable = Variable
                } = Packet,
                Qos = Header#mqtt_packet_header.qos,
                Topic = Variable#mqtt_packet_publish.topic_name,
                FromUid =
                case string:tokens(binary_to_list(Topic), "@") of
                    [ _Type, FromUserName0 ] ->
                        list_to_binary( FromUserName0 );
                    _CantSplite ->
                        <<"undefined">>
                end,
                NewMsgId = off_msg_id_svc:get_msg_id(),
                gen_server:cast( SelfPid, {route_offmsg_client, Username, Qos, Topic, Content, NewMsgId }),
                off_msg_api: new_tmp_person_msg(Username, NewMsgId, FromUid, Topic, Content, Qos, not_ios, NowTime )
            end,
            lists:foreach( Fun, AWaitAckList )
    end.

% -------------------------------------------------------------------------------
% 将未回复ACK的消息存储到离线消息中，单如果超过 1000 消息未回ACK则直接丢弃
% -------------------------------------------------------------------------------
fail_msg_to_offmsg( Username ) ->
    AWaitAckList = emqttd_am:load(Username),
    util:print("fail msg to offmsg ~p ~p ~n",[ Username, AWaitAckList ]),
    NowTime = util:longunixtime(),
    case length(AWaitAckList) > 1000 of
        true -> ok;
        false ->
            Fun = fun( Packet ) ->
                #mqtt_packet{
                    payload = Content,
                    header = Header,
                    variable = Variable
                } = Packet,
                Qos = Header#mqtt_packet_header.qos,
                Topic = Variable#mqtt_packet_publish.topic_name,
                FromUid =
                case string:tokens(binary_to_list(Topic), "@") of
                    [ _Type, FromUserName0 ] ->
                        list_to_binary( FromUserName0 );
                    _CantSplite ->
                        <<"undefined">>
                end,
                NewMsgId = off_msg_id_svc:get_msg_id(),
                off_msg_api: new_tmp_person_msg(Username, NewMsgId, FromUid, Topic, Content, Qos, not_ios, NowTime )
            end,
            lists:foreach( Fun, AWaitAckList )
    end.    


% ---------------------------------------------------------------------------------
% 进程结束 处理业务
% 1: 将没有来得及发送成功的消息，写入到离线
% 2: 通知状态订阅者
% 3: 记录到log
% 4: emqttd_proto:shutdown 
% ---------------------------------------------------------------------------------
shutdown(Username, _SubList, Error, ProtoState, Ip) ->
    fail_msg_to_offmsg(Username),
    login_info(Username, Ip, 0, Error),
    emqttd_protocol:shutdown(Error, ProtoState).

% ===============================================================================================================
%                                               用户下线处理
% ===============================================================================================================
%% terminate处理业务
terminate(Reason, KeepAlive, ProtoState, SubList) ->
    try
        Username = emqttd_protocol:client_id(ProtoState),
        case Username of
            undefined ->
                ok;
            _NotUndefined ->
                emqttd_keepalive:cancel(KeepAlive),
                [UserInfo] = mnesia:dirty_read(user_info, Username),

                % ------------------------------------------------------------------------------
                %       如果用户是被踢下线，那这里不需要把等待返回ACK的数据包转存到离线消息
                % ------------------------------------------------------------------------------
                util:print("[terminate] => [Username:~p,Reason:~p] ~n",[Username, Reason]),
                case {ProtoState, Reason} of
                    {undefined, _} -> ok;
                    {_, {shutdown, duplicate_id}} ->
                        login_info(Username, UserInfo#user_info.ip, 0, duplicate),
                        ok;
                    {_, {shutdown, duplicate}} ->
                        case Username =/= undefined of
                            true ->
                                shutdown(Username, SubList, duplicate, ProtoState, UserInfo#user_info.ip);
                            false ->
                                ok
                        end;
                    {_, {shutdown, Error}} ->
                        case Username =/= undefined of
                            true ->
                                mnesia_tools:dirty_write(user_info, UserInfo#user_info{status = 0}),

                                StateSubscribeList = do_get_sub_satus_list( UserInfo ),
                                send_state_subscribe_msg(StateSubscribeList, Username, offline),

                                shutdown(Username, SubList, Error, ProtoState, UserInfo#user_info.ip);
                            false ->
                                ok
                        end;
                    {_, _} -> 
                        ok
                end
        end
    catch
        M:R ->
            lager:error(" client terminate error. M:~p R:~p ~n ~p ~n",[ M, R, erlang:get_stacktrace() ])
    end. 

do_get_sub_satus_list( UserInfo ) ->

    OldMap = UserInfo#user_info.apply_time,
    case erlang:is_map(OldMap) of
        true ->
            maps:get( sub_state_list , OldMap, [ ] );
        _OldTrue ->
            []
    end.

%% gen_server handle_call
handle_call(Req, _From, State) ->
    {reply, {badreq, Req}, State}.

%% gen_server handle_cast
handle_cast(_Msg, State) ->
    {noreply, State}.

%% gen_server handle_info
handle_info(Info, State = #state{peer_name = PeerName}) ->
    lager:critical("Client ~p: unexpected info ~p",[PeerName, Info]),
    {noreply, State}.

%% 发送消息
send_message(SendFun, Packet1, Username, PacketId, Qos) ->
    Variable = Packet1#mqtt_packet.variable, 
    Packet = Packet1#mqtt_packet{variable = Variable#mqtt_packet_publish{packet_id = PacketId}},
    Data = emqttd_serialiser:serialise(Packet),
    SendFun(Data),
    case Qos  =:= undefined  orelse Qos =:= 0 of
        true  -> ok;
        false -> 
            %% %% 添加await_ack
            emqttd_am:awaiting_ack(Username, PacketId, Packet)
    end,
    lager:debug("send_message---SENT to ~ts", [emqttd_packet:dump(Packet)]).

%% 发送离线消息
send_off_message(SendFun, Username, PacketId1, OffMsgList) ->
    PacketId2 = lists:foldl(
        fun(#off_msg{id = _Id, topic = Topic, message = Message, volume = _Volume, qos = Qos}, AccInPacketId) ->
            {ThisPacketId, NewAccInPacketId} = case Qos > 0 of
                true  -> {AccInPacketId, AccInPacketId + 1};
                false -> {undefined, AccInPacketId}
            end,
            NewPacket = ?PUBLISH_PACKET(Qos, Topic, ThisPacketId, Message),
            send_message(SendFun, NewPacket, Username, ThisPacketId, Qos),
            NewAccInPacketId
        end, PacketId1, OffMsgList),
    %% 用户上线后，发送离线消息，然后删除数据
    emqttd_mm:delete_off_msg(Username, OffMsgList),
    PacketId2.

%% 发送状态消息(包括本节点和其他节点)
send_state_subscribe_msg([], _, _) ->
    ok;
    
send_state_subscribe_msg(StateSubscribeList, Username, Status) ->
    try
        lists:foreach(
            fun(Item) ->
                [User] = mnesia_tools:dirty_read(users, Item),
                [UserInfo] = mnesia_tools:dirty_read(user_info, Item),
                case UserInfo#user_info.platform_type =:= ?H_SDK of
                    true  ->
                        case Status of
                            online  -> emqttd_ham:send_sub_state(UserInfo#user_info.appkey, Username, Item, 1);
                            offline -> emqttd_ham:send_sub_state(UserInfo#user_info.appkey, Username, Item, 0)
                        end;
                    false -> 
                        case User#users.node_id =:= mnesia_tools:get_node_id() of
                            true ->
                                send_state_subscribe_msg1(Username, Item, Status);
                            false ->
                                case mnesia_tools:dirty_read(nodes, User#users.node_id) of
                                    [] -> 
                                        lager:error("Node~p is ont find", [User#users.node_id]),
                                        ok;
                                    [Node] ->
                                        cast_svc:cast(Node#nodes.node, ?MODULE, send_state_subscribe_msg1, [Username, Item, Status])
                                end
                        end
                end
            end, StateSubscribeList)
    catch
        M:R ->
            lager:error("send state subscribe msg error ~p ~p ~n ~p ~n", [ M, R, erlang:get_stacktrace() ])
    end.    


send_state_subscribe_msg1(Username, Item, Status) ->
    case emqttd_cm:lookup(Item) of
        undefined -> ok;
        Pid ->
            Topic = 
                case Status of
                    online  -> ?OFLINE;
                    offline -> ?OFFLINE
                end,
            Topic1 = <<Topic/binary, Username/binary>>,
            gen_server:cast(Pid, {send_msg, ?QOS_0, Topic1, <<"">>})
    end.     

%% 添加好友通知
notice_add_buddy(Username, FriendId) ->
    case emqttd_cm:lookup(Username) of
        undefined -> ok;
        Pid -> gen_server:cast(Pid, {notice_add_buddy, FriendId})
    end.

%% 删除好友通知
notice_remove_buddy(Username, FriendId) ->
    case emqttd_cm:lookup(Username) of
        undefined -> ok;
        Pid -> gen_server:cast(Pid, {notice_remove_buddy, FriendId})
    end. 

% -------------------------------------------------------------------
% 通知其他节点，被重复登录，结束当前节点进程
% -------------------------------------------------------------------
notify_duplicate( Username, Node, SelfPid ) ->
    case emqttd_cm:lookup(Username) of
        undefined -> ok;
        Pid ->
            AWaitAckList = emqttd_am:load( Username ),
            cast_svc:cast( Node, emqttd_client_tools, send_no_ack_msgs, [ Username, SelfPid, AWaitAckList ] ),
            Pid ! {stop, duplicate, Node}
    end.    

%% packet_id如果等于65535,则置为1
check_packet_id(PacketId)  when PacketId == 65535 ->
    1;
check_packet_id(PacketId)->
    PacketId.    

msg_info(FromUsername, Username, Payload, Type) ->
    case util:get_value_cache( emqttd, msg_log_flag, undefined ) of
        undefined ->
            ok;
        0 ->
            ok;
        1 ->
            case emqttd_core_ets:lookup_node(application:get_env(emqttd, log_server, undefined)) of
                undefined ->
                    %lager:error("Not find login_server node"),
                    ok;
                Node ->
                    cast_svc:cast(Node, log_server_core, msg_info, [FromUsername, Username, Payload, Type])
            end
    end.

% ------------------------------------------------------------------------------------------------
%                               写入到登录的事件中去。
% ------------------------------------------------------------------------------------------------
login_info(Username, Ip, Tpye, Cause) ->
    case emqttd_core_ets:lookup_node(application:get_env(emqttd, log_server, undefined)) of
        undefined ->
            %lager:error("Not find login_server node"),
            ok;
        Node ->
            cast_svc:cast(Node, log_server_core, login_info, [Username, Ip, Tpye, Cause])
    end.        
