%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd protocol.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_protocol).

-include("emqttd.hrl").

-include("emqttd_packet.hrl").

-define( DEFAULT_AUTH_MODULE,   emqttd_auth_internal).      % 默认的帐号密码校验模块

%% API
-export([init/3, client_id/1, username/1, client/1]).

-export([received/2, send/2, shutdown/2]).

%% Protocol State
-record(proto_state, {
        sendfun,
        peer_name,
        connected = false, %received CONNECT action?
        proto_ver,
        proto_name,
        client_id,
        clean_sess,
        max_clientid_len = ?MAX_CLIENTID_LEN,
        username,
        packet,
        client_pid,
        sess_pid
}).

-type proto_state() :: #proto_state{}.

init(Peername, SendFun, _Opts) ->
    #proto_state{
        sendfun          =  SendFun,
        peer_name        = Peername,
        max_clientid_len = 1024,
        client_pid       = self()}. 

client_id(#proto_state{client_id = ClientId}) -> ClientId.
username(#proto_state{username = Username}) -> Username.

client(#proto_state{peer_name = {Addr, _Port},
                    client_id = ClientId,
                    username = Username,
                    clean_sess = CleanSess,
                    proto_ver  = ProtoVer,
                    client_pid = Pid}) ->
    #mqtt_client{clientid   = ClientId,
                 username   = Username,
                 ipaddress  = Addr,
                 clean_sess = CleanSess,
                 proto_ver  = ProtoVer,
                 client_pid = Pid}.


%%CONNECT – Client requests a connection to a Server

%%A Client can only send the CONNECT Packet once over a Network Connection. 
-spec received(mqtt_packet(), proto_state()) -> {ok, proto_state()} | {error, any()}. 
received(Packet = ?PACKET(?CONNECT), State = #proto_state{connected = false, peer_name = PeerName, client_id = ClientId}) ->
    lager:debug("RECV from ~p@~p: ~ts", [ClientId, PeerName, emqttd_packet:dump(Packet)]),
    handle(Packet, State#proto_state{connected = true});

received(?PACKET(?CONNECT), State = #proto_state{connected = true}) ->
    {error, protocol_bad_connect, State};

%%Received other packets when CONNECT not arrived.
received(_Packet, State = #proto_state{connected = false}) ->
    {error, protocol_not_connected, State};

received(Packet = ?PACKET(_Type), State = #proto_state{peer_name = PeerName, client_id = ClientId}) ->
    lager:debug("RECV from ~p@~p: ~ts", [ClientId, PeerName, emqttd_packet:dump(Packet)]),
    case validate_packet(Packet) of 
    ok ->

        % -------------------------------------------------
        % 如果收到的不是心跳包，那么设置不休眠。
        % --------------------------------------------------
        case Packet of
            ?PACKET(?PINGREQ) ->
                skip;
            _NotPing ->
                emqttd_client:no_hibernate()
        end,
        % --------------------------------------------------

        handle(Packet, State);
    {error, Reason} ->
        {error, Reason, State}
    end.

handle(?CONNECT_PACKET(Var), State = #proto_state{peer_name = PeerName}) ->
    #mqtt_packet_connect{proto_ver   = ProtoVer,
                         username    = Username,
                         password    = Password,
                         clean_sess  = CleanSess,
                         keep_alive  = KeepAlive,
                         client_id   = ClientId} = Var,
    case util:get_value( mem_rate_can_login, true ) of
        true ->
            case validate_connect(Var, State) of
                ?CONNACK_ACCEPT ->
                    {PlatformType, Type, _ProtocolVersion} = get_platform_type(ClientId),
                    AuthCheckModule = ?DEFAULT_AUTH_MODULE,
                    %-% 获取密码校验的模块
                        case true of % AuthCheckModule:check(Username, Password, PlatformType) of
                            true ->

                                % ----------------------------------------------------------------- %
                                % 注册唯一的 Uid 到emqttd_cm
                                % ----------------------------------------------------------------- % 
                                emqttd_cm:register(client(State#proto_state{client_id  = Username })),

                                {ok, SessPid} = emqttd_session:start_link( CleanSess ),
                                NewState = State#proto_state{proto_ver  = ProtoVer,
                                                                    client_id  = Username,
                                                                    clean_sess = CleanSess,
                                                                    username   = Username,
                                                                    sess_pid   = SessPid},

                                start_keepalive(KeepAlive),
                                send(?CONNACK_PACKET(?CONNACK_ACCEPT), NewState),
                                Pid = emqttd_cm:lookup( Username ),
                                case CleanSess of
                                    true ->
                                        ok;
                                    false ->
                                        emqttd_am:load( Username ),
                                        off_msg_api: clean_offmsg( Username )
                                end,
                                update_info( Type, Pid, Username ),
                                util:print("[login] => [UserName:~p,PlatformType:~p]~n", [ Username, Type ] ),
                                {ok, NewState};
                            false ->
                                NewStateFalse =  State#proto_state{client_id = undefined, clean_sess = false, username = undefined},
                                send(?CONNACK_PACKET(?CONNACK_CREDENTIALS), NewStateFalse ),
                                lager:error("~p@~p: username '~p' login failed - no credentials", [Username, PeerName, Username]),
                                {stop, normal, NewStateFalse}
                        end;
                ReturnCode ->
                    NewStateOther = State#proto_state{client_id = undefined, clean_sess = CleanSess},
                    send(?CONNACK_PACKET(ReturnCode), NewStateOther ),
                    {stop, normal, NewStateOther}
            end;
        _OthersMemoryFullNotTrue ->
            %-% 服务器内存紧张，拒绝登录新用户。
            NewStateOther = State#proto_state{client_id = undefined, clean_sess = CleanSess},
            send(?CONNACK_PACKET(?CONNACK_SERVER), NewStateOther ),
            {stop, normal, NewStateOther}
    end;

handle(Packet = ?PUBLISH_PACKET(?QOS_0, Topic, _PacketId, Payload),
       State = #proto_state{client_id = Username, sendfun = SendFun, sess_pid = SessPid}) ->
    emqttd_session:router(SessPid, Packet, Topic, Payload, Username, SendFun),
    % emqttd_route:route(Packet, Topic, Payload, Username, SendFun),
    {ok, State};

handle(Packet = ?PUBLISH_PACKET(?QOS_1, Topic, PacketId, Payload), 
       State = #proto_state{client_id = Username, sendfun = SendFun, sess_pid = SessPid}) ->
    emqttd_session:router(SessPid, Packet, Topic, Payload, Username, SendFun),
    % emqttd_route:route(Packet, Topic, Payload, Username, SendFun),
    send(?PUBACK_PACKET(?PUBACK, PacketId), State);
    
handle(Packet = ?PUBLISH_PACKET(?QOS_2, Topic, PacketId, Payload), State = #proto_state{packet = Packet1}) when Packet1 =:= undefined ->
    NewPacket = [{PacketId, Topic, Payload, Packet}],
    send(?PUBACK_PACKET(?PUBREC, PacketId), State#proto_state{packet = NewPacket});

handle(Packet = ?PUBLISH_PACKET(?QOS_2, Topic, PacketId, Payload), State = #proto_state{packet = Packet1}) ->
    NewPacket = Packet1 ++ [{PacketId, Topic, Payload, Packet}],
    send(?PUBACK_PACKET(?PUBREC, PacketId), State#proto_state{packet = NewPacket});


handle(?PUBACK_PACKET(Type, PacketId), State = #proto_state{username = Username, packet = Packets}) 
    when Type >= ?PUBACK andalso Type =< ?PUBCOMP andalso Packets =:= undefined ->
    if 
        Type =:= ?PUBREC ->
            send(?PUBREL_PACKET(PacketId), State);
        Type =:= ?PUBREL ->
            send(?PUBACK_PACKET(?PUBCOMP, PacketId), State);
        true ->
            %% 解除await_ack
            emqttd_am:un_awaiting_ack(Username, PacketId),
            ok
    end,
    {ok, State};
  
handle(?PUBACK_PACKET(Type, PacketId), State = #proto_state{client_id = Username, packet = Packets, sendfun = SendFun, sess_pid = SessPid}) 
    when Type >= ?PUBACK andalso Type =< ?PUBCOMP ->
    NewPackets =
        case lists:keyfind(PacketId, 1, Packets) of
            false -> 
                lager:error("Not find packetid is:~p data~n", [PacketId]),
                Packets;
            {PacketId, Topic, Payload, Packet} ->
                emqttd_session:router(SessPid, Packet, Topic, Payload, Username, SendFun),
                % emqttd_route:route(Packet, Topic, Payload, Username, SendFun),
                lists:delete({PacketId, Topic, Payload, Packet}, Packets)
        end,
    if 
        Type =:= ?PUBREC ->
            send(?PUBREL_PACKET(PacketId), State);
        Type =:= ?PUBREL ->
            send(?PUBACK_PACKET(?PUBCOMP, PacketId), State);
        true ->
            %% 解除await_ack
            emqttd_am:un_awaiting_ack(Username, PacketId),
            ok
    end,
    {ok, State#proto_state{packet = NewPackets}};

handle(?SUBSCRIBE_PACKET(PacketId, TopicTable), State = #proto_state{username = Username}) ->
    Res = emqttd_pubsub:subscribe(TopicTable, Username),
    {ok, GrantedQos} = Res,
    send(?SUBACK_PACKET(PacketId, GrantedQos), State);

handle(?UNSUBSCRIBE_PACKET(PacketId, Topics), State = #proto_state{username = Username}) ->
    emqttd_pubsub:unsubscribe(Topics, Username),
    send(?UNSUBACK_PACKET(PacketId), State);

handle(?PACKET(?PINGREQ), State = #proto_state{username = Username}) ->
    {_, List} = lists:foldl(fun(_, {Base, AccIn}) -> {Base+10000, AccIn ++ [integer_to_binary(Base)]} end, {10000, []},lists:seq(1, 100)),
    case lists:member(Username, List) of
        true -> lager:info("received to Username:~p is ping packet~n", [Username]);
        false -> ok
    end,
    send(?PACKET(?PINGRESP), State);

handle(?PACKET(?DISCONNECT), State) ->
    {stop, normal, State}.

-spec send({pid() | tuple(), mqtt_message()} | mqtt_packet(), proto_state()) -> {ok, proto_state()}.
send({_From, Message = #mqtt_message{qos = ?QOS_0}}, State) ->
    send(emqttd_message:to_packet(Message), State);

%% message(qos1, qos2)
send({_From, Message = #mqtt_message{qos = Qos}}, #proto_state{username = Username} = State) when (Qos =:= ?QOS_1) orelse (Qos =:= ?QOS_2) ->
    Message1 = if
        Qos =:= ?QOS_2 -> Message#mqtt_message{dup = false};
        true -> Message
    end,
    Packet = emqttd_message:to_packet(Message1),
    {ok, NewState} = send(Packet, State),
    %% %% 添加await_ack
    emqttd_am:awaiting_ack(Username, Message1#mqtt_message.msgid, Packet),
    {ok, NewState};

send({_From, Message}, State)->
    send(emqttd_message:to_packet(Message), State);

send(Packet, State = #proto_state{sendfun = SendFun, peer_name = PeerName, client_id = ClientId}) when is_record(Packet, mqtt_packet) ->
    Data = emqttd_serialiser:serialise(Packet),
    SendFun(Data),
    lager:debug("SENT to ~p@~p: ~ts", [ClientId, PeerName, emqttd_packet:dump(Packet)]),
    {ok, State}.

shutdown(Error, #proto_state{peer_name = PeerName, client_id = ClientId, username = Username, sess_pid = SessPid}) ->
    case Username =:= undefined of
        true -> ok;
        false ->try_unregister(ClientId)
    end,
    case SessPid =:= undefined of
        true -> ok;
        false -> SessPid ! close
    end,
    lager:debug("Protocol ~p@~p Shutdown: ~p", [ClientId, PeerName, Error]),
    ok.

% clientid(<<>>, #proto_state{peer_name = PeerName}) ->
%     <<"eMQTT/", (base64:encode(PeerName))/binary>>;

% clientid(ClientId, _State) -> ClientId.

%%----------------------------------------------------------------------------
start_keepalive(0) -> ignore;
start_keepalive(Sec) when Sec > 0 ->
    self() ! {keepalive, start, round(Sec * 1.5)}.

%%----------------------------------------------------------------------------
%% Validate Packets
%%----------------------------------------------------------------------------
validate_connect(Connect = #mqtt_packet_connect{}, ProtoState) ->
    case validate_protocol(Connect) of
        true -> 
            case validate_clientid(Connect, ProtoState) of
                true -> 
                    ?CONNACK_ACCEPT;
                false -> 
                    ?CONNACK_INVALID_ID
            end;
        false -> 
            ?CONNACK_PROTO_VER
    end.

validate_protocol(#mqtt_packet_connect{proto_ver = Ver, proto_name = Name}) ->
    lists:member({Ver, Name}, ?PROTOCOL_NAMES).

validate_clientid(#mqtt_packet_connect{client_id = ClientId}, #proto_state{max_clientid_len = MaxLen})
    when ( size(ClientId) >= 1 ) andalso ( size(ClientId) =< MaxLen ) ->
    true;

%% MQTT3.1.1 allow null clientId.
validate_clientid(#mqtt_packet_connect{proto_ver =?MQTT_PROTO_V311, client_id = ClientId}, _ProtoState) 
    when size(ClientId) =:= 0 ->
    true;

validate_clientid(#mqtt_packet_connect {proto_ver = Ver, clean_sess = CleanSess, client_id = ClientId}, _ProtoState) -> 
    lager:warning("Invalid ClientId: ~p, ProtoVer: ~p, CleanSess: ~p", [ClientId, Ver, CleanSess]),
    false.

validate_packet(#mqtt_packet{header  = #mqtt_packet_header{type = ?PUBLISH}, 
                             variable = #mqtt_packet_publish{topic_name = Topic}}) ->
    case emqttd_topic:validate({name, Topic}) of
    true -> ok;
    false -> lager:warning("Error publish topic: ~p", [Topic]), {error, badtopic}
    end;

validate_packet(#mqtt_packet{header  = #mqtt_packet_header{type = ?SUBSCRIBE},
                             variable = #mqtt_packet_subscribe{topic_table = Topics}}) ->

    validate_topics(filter, Topics);

validate_packet(#mqtt_packet{ header  = #mqtt_packet_header{type = ?UNSUBSCRIBE}, 
                              variable = #mqtt_packet_subscribe{topic_table = Topics}}) ->

    validate_topics(filter, Topics);

validate_packet(_Packet) -> 
    ok.

validate_topics(Type, []) when Type =:= name orelse Type =:= filter ->
    lager:error("Empty Topics!"),
    {error, empty_topics};

validate_topics(Type, Topics) when Type =:= name orelse Type =:= filter ->
    ErrTopics = [Topic || {Topic, Qos} <- Topics,
                        not (emqttd_topic:validate({Type, Topic}) and validate_qos(Qos))],
    case ErrTopics of
    [] -> ok;
    _ -> lager:error("Error Topics: ~p", [ErrTopics]), {error, badtopic}
    end.

validate_qos(undefined) -> true;
validate_qos(Qos) when Qos =< ?QOS_2 -> true;
validate_qos(_) -> false.

try_unregister(ClientId) -> emqttd_cm:unregister(ClientId).

get_platform_type(ClientId) ->
    ClientIdArgs = string:tokens(binary_to_list(ClientId), "@"),
    case length(ClientIdArgs) > 1 of
        true ->
            [_, ParamsArgs] = ClientIdArgs,
            ParamsArgs2 = string:tokens(ParamsArgs, "|"),
            {Type, _Version, ProtocolVersion} = 
                case length(ParamsArgs2) of
                    3 ->
                        [Type1, Version1, ProtocolVersion1] = ParamsArgs2, 
                        {Type1, Version1, ProtocolVersion1};
                    2 ->
                        [Type1, Version1] = ParamsArgs2,
                        {Type1, Version1, undefined};
                    1 ->
                        [Type1] = ParamsArgs2,
                        {Type1, undefined, undefined}
                end,
            PlatformType =  case Type of
                "1" -> ?A_SDK;
                "2" -> ?J_SDK;
                "3" -> ?L_SDK;
                "4" -> ?U_SDK;
                "5" -> ?W_SDK;
                "6" -> ?S_SDK;
                "7" -> ?I_SDK;
                _   -> ?I_SDK
            end,
            {PlatformType, Type, ProtocolVersion};
        false ->
            {undefined, undefined}
    end.

update_info(PlatformType, Pid, Username) ->
    case PlatformType of
        "1" -> 
            gen_server:cast(Pid, {update_info, Username, ?A_SDK});
        "2" -> 
            gen_server:cast(Pid, {update_info, Username, ?J_SDK});
        "3" ->
            gen_server:cast(Pid, {update_info, Username, ?L_SDK}); 
        "4" -> 
            gen_server:cast(Pid, {update_info, Username, ?U_SDK});
        "5" -> 
            gen_server:cast(Pid, {update_info, Username, ?W_SDK});
        "6" -> 
            gen_server:cast(Pid, {update_info, Username, ?S_SDK});
        "7" -> 
            gen_server:cast(Pid, {update_info, Username, ?I_SDK});            
        undefined ->
            gen_server:cast(Pid, {update_info, Username});
        IOSToken ->
            gen_server:cast(Pid, {update_info, Username, ?I_SDK, IOSToken})

    end.   
