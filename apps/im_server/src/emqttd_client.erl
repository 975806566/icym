%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd client.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_client).

-behaviour(gen_server).

-export([start_link/2]).

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        code_change/3,
        terminate/2]).

-export([
        no_hibernate/0,
        get_hibernate_state/1,
        clear_hibernate/0
        ]).

-include("emqttd.hrl").

-include("emqttd_packet.hrl").

-define(LENGTH, 100).
-define(HIBERNATE_KEY,      '$_hibernate').

%%Client State...
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

start_link(Connection, MqttEnv) ->
    {ok, proc_lib:spawn_link(?MODULE, init, [[Connection, MqttEnv]])}.

init([OriginConn, MqttEnv]) ->
    {ok, Connection} = OriginConn:wait(),
    {_, _, PeerName} =
        case Connection:peername() of
            {ok, Peer = {Host, Port}} ->
                {Host, Port, Peer};
            {error, enotconn} ->
                Connection:fast_close(),
                exit(normal);
            {error, Reason} ->
                Connection:fast_close(),
                exit({shutdown, Reason})
        end,
    ConnName = esockd_net:format(PeerName),

    Self = self(),
    SendFun = fun(Data) ->
        try Connection:async_send(Data) of
            true -> ok
        catch
            error:Error -> Self ! {shutdown, Error}
        end
    end,
    
    Sock = Connection:sock(),
    inet:setopts(Sock,[{high_watermark,131072},{low_watermark, 65536}]),

    PktOpts = proplists:get_value(packet, MqttEnv),
    ParserFun = emqttd_parser:new(PktOpts),
    ProtoState = emqttd_protocol:init(PeerName, SendFun, PktOpts),
    RateLimit = proplists:get_value(rate_limit, Connection:opts()),
    State = run_socket(#state{connection   = Connection,
                                     conn_name    = ConnName,
                                     peer_name    = PeerName,
                                     await_recv   = false,
                                     conn_state   = running,
                                     rate_limit   = RateLimit,
                                     parser_fun   = ParserFun,
                                     proto_state  = ProtoState,
                                     packet_opts  = PktOpts,
                                     sendfun      = SendFun,
                                     packet_id    = 1,
                                     sub_list     = []}),
    ClientOpts = proplists:get_value(client, MqttEnv),
    IdleTimout = proplists:get_value(idle_timeout, ClientOpts, 10),
    no_hibernate(),
    gen_server:enter_loop(?MODULE, [], State, timer:seconds(IdleTimout)).      

handle_call(Req, From, State) ->
    emqttd_client_tools:handle_call(Req, From, State).  

%%----------------------------------------
%% 用户上线，更新用户登录信息
%%----------------------------------------
handle_cast({update_info, Username}, State) ->
    handle_cast({update_info, Username, undefined}, State);
handle_cast({update_info, Username, PlatformType}, State) ->
    handle_cast({update_info, Username, PlatformType, undefined}, State);
handle_cast({update_info, Username, PlatformType, IOSToken}, State) ->
    emqttd_client_tools:update_info( Username, PlatformType, IOSToken, State#state.peer_name ),
    {noreply, State};



% ===============================================================================================================
%                              @doc 离线消息这块的接口
%                              1: 批量推送离线消息。
%                              2: 清空所有的离线消息数据
%
%                              @doc 离线消息的定义。只有存储到离线服务上面的消息才认为是离线消息。
%                              @attention emqttd_am 中没有收到ack的消息，被认为是在线消息。
% ===============================================================================================================

% --------------------------------------------------------------
% 供给离线服务调用的接口。批量推送离线消息给前端
% --------------------------------------------------------------
handle_cast({route_offmsg, OffMsgList}, State ) ->
    Fun = fun({ UserId, MsgId, _FromId, Topic, Content, _Type, Qos }, _AccList) ->
            gen_server:cast(self(),{route_offmsg_client, UserId, Qos, Topic, Content, MsgId })   
    end,
    lists:foldr( Fun, [], OffMsgList ),
    {noreply, State};

handle_cast({route_offmsg_client, UserId, Qos, Topic, Content, MsgId}, State = #state{sendfun = SendFun, packet_id = PacketId3}) ->
    PacketId = emqttd_client_tools:check_packet_id(PacketId3),
    emqttd_mm:insert_pgk_msg_id(UserId, PacketId, MsgId ),
    NewPacket= ?PUBLISH_PACKET(Qos, Topic, PacketId, Content),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    {noreply, State#state{ packet_id = PacketId + 1}};




% ================================================================================================================
%                               以下是服务器发送消息给前端的最直接的接口
%                               1: Qos0 直接发送，没有ack机制保证
%                               2: Qos1 保证至少发送一次
%                               3: Qos2 保证只交互一次
% ================================================================================================================
%%----------------------------------------
%% 消息发送 QOS0
%%----------------------------------------
handle_cast({send_msg, ?QOS_0, Topic, Payload}, State) ->
    handle_cast({send_msg, undefined, ?QOS_0, Topic, Payload}, State);
handle_cast({send_msg, _Uid, ?QOS_0, Topic, Payload}, State = #state{sendfun = SendFun}) ->
    NewPacket= ?PUBLISH_PACKET(?QOS_0, Topic, undefined, Payload),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    lager:debug("send_msg QOS_0---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    {noreply, State};

%%----------------------------------------
%% 消息发送 QOS1 or QOS2
%%----------------------------------------
handle_cast({send_msg, Username, Qos, Topic, Payload}, State = #state{sendfun = SendFun, packet_id = PacketId3}) ->
    PacketId = emqttd_client_tools:check_packet_id(PacketId3),
    NewPacket= ?PUBLISH_PACKET(Qos, Topic, PacketId, Payload),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    %% 添加await_ack
    emqttd_am:awaiting_ack(Username, PacketId, NewPacket),
    lager:debug("send_msg QOS_1 or QOS_2---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    {noreply, State#state{ packet_id = PacketId + 1}};

%%----------------------------------------
%% 发送群消息
%%----------------------------------------
handle_cast({send_pub_msg, Msg, ?QOS_0, _}, #state{sendfun = SendFun} = State)->
    NewPacket = emqttd_message:to_packet(Msg),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    lager:debug("send_msg QOS0---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    {noreply, State};
handle_cast({send_pub_msg, Msg, _, Username}, #state{sendfun = SendFun, packet_id = PacketId3} = State)->
    PacketId = emqttd_client_tools:check_packet_id(PacketId3),
    Msg2 = Msg#mqtt_message{msgid = PacketId},
    NewPacket = emqttd_message:to_packet(Msg2),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    %% 添加await_ack
    emqttd_am:awaiting_ack(Username, PacketId, NewPacket),
    lager:debug("send_msg QOS1 or QOS2---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    {noreply, State#state{ packet_id = PacketId + 1}};

% ================================================================================================================
%                                       好友这块的接口
% ================================================================================================================
%% 添加好友通知消息
handle_cast({notice_add_buddy, Username}, State = #state{sendfun = SendFun}) ->
    Topic = lists:concat([?NOTICE_ADD_BUDDY, "@", binary_to_list(Username)]),
    NewPacket= ?PUBLISH_PACKET(?QOS_0, list_to_binary(Topic), undefined, <<"">>),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    lager:debug("notice_add_buddy---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    {noreply, State};

%% 删除好友通知消息
handle_cast({notice_remove_buddy, Username}, State = #state{sendfun = SendFun}) ->
    Topic = lists:concat([?NOTICE_REMOVE_BUDDY, "@", binary_to_list(Username)]),
    NewPacket= ?PUBLISH_PACKET(?QOS_0, list_to_binary(Topic), undefined, <<"">>),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    lager:debug("notice_remove_buddy---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    {noreply, State};

handle_cast(Msg, State) ->
    emqttd_client_tools:handle_cast(Msg, State).

handle_info(timeout, State) ->
    stop({shutdown, timeout}, State);

%% 在本节点被他人登录
handle_info({stop, duplicate_id, _}, State=#state{proto_state = ProtoState,
                                                  peer_name   = Peername,
                                                  conn_name   = ConnName,
                                                  sendfun     = SendFun}) ->
    lager:error("Shutdown for duplicate clientid: ~p, conn:~p, ~p", [emqttd_protocol:client_id(ProtoState), ConnName, Peername]),
    NewPacket = ?PUBLISH_PACKET(?QOS_0, ?SYSKICK, undefined, <<"Your account is already logged in elsewhere">>),
    emqttd_client_tools:send_message(SendFun, NewPacket, <<"">>, undefined, ?QOS_0),
    stop({shutdown, duplicate_id}, State);

%% 在其他节点被他人登录
handle_info({stop, duplicate, Node}, State=#state{proto_state = ProtoState,
                                                  peer_name   = Peername,
                                                  conn_name   = ConnName,
                                                  sendfun     = SendFun}) ->
    lager:error("Shutdown for duplicate node:~p, clientid: ~p, conn:~p, ~p", [Node, emqttd_protocol:client_id(ProtoState), ConnName, Peername]),
    NewPacket = ?PUBLISH_PACKET(?QOS_0, ?SYSKICK, undefined, <<"Your account is already logged in elsewhere">>),
    emqttd_client_tools:send_message(SendFun, NewPacket, <<"">>, undefined, ?QOS_0),
    stop({shutdown, duplicate}, State);    


% ==============================================================================================================
%               emqttd socket 方面，以及其他网络方面的底层
% ==============================================================================================================
handle_info(activate_sock, State) ->
    {noreply, run_socket(State#state{conn_state = running})};

handle_info({inet_async, _Sock, _Ref, {ok, Data}}, State) when is_list(Data)->
    handle_info({inet_async, _Sock, _Ref, {ok, list_to_binary(Data)}}, State);    
handle_info({inet_async, _Sock, _Ref, {ok, Data}}, State) ->
    Size = size(Data),
    received(Data, rate_limit(Size, State#state{await_recv = false}));

handle_info({inet_async, _Sock, _Ref, {error, Reason}}, State) ->
    shutdown(Reason, State);

handle_info({inet_reply, _Sock, ok}, State) ->
    {noreply, State };

handle_info({inet_reply, _Sock, {error, Reason}}, State = #state{peer_name = PeerName}) ->
    lager:critical("Client ~p: unexpected inet_reply '~p'", [PeerName, Reason]),
    shutdown(Reason, State);

handle_info({keepalive, start, Interval}, State = #state{connection = Connection}) ->
    lager:debug("Client ~p: Start KeepAlive with ~p seconds", [State#state.peer_name, Interval]),
    StatFun = fun() ->
                case Connection:getstat([recv_oct]) of
                    {ok, [{recv_oct, RecvOct}]} -> {ok, RecvOct};
                    {error, Error}              -> {error, Error}
                end
             end,
    KeepAlive = emqttd_keepalive:start(StatFun, Interval, {keepalive, check}),
    {noreply, State#state{keepalive = KeepAlive}};

handle_info({keepalive, check}, State = #state{keepalive = KeepAlive}) ->
    case emqttd_keepalive:check(KeepAlive) of
        {ok, KeepAlive1} ->
            get_hibernate_state( State#state{keepalive = KeepAlive1} ) ;
        {error, timeout} ->
            lager:warning("Keepalive timeout", []),
            shutdown(keepalive_timeout, State);
        {error, Error} ->
            lager:warning("Keepalive error - ~p", [Error]),
            shutdown(Error, State)
    end;    

handle_info(Info, State) ->
    emqttd_client_tools:handle_info(Info, State).

terminate(Reason, #state{ keepalive = KeepAlive, proto_state = ProtoState, sub_list = SubList }) ->
    emqttd_client_tools:terminate(Reason, KeepAlive, ProtoState, SubList).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%----------------------------------------------------------------------------
% network_error(Reason, State = #state{peer_name = PeerName}) ->
%     lager:warning("Client ~p: MQTT detected network error '~p'", [PeerName, Reason]),
%     stop({shutdown, conn_closed}, State).

%-------------------------------------------------------
% Receive and parse tcp data
%-------------------------------------------------------
received(<<>>, State) ->
    {noreply, State};

received(Bytes, State = #state{parser_fun  = ParserFun,
                                      packet_opts = PacketOpts,
                                      proto_state = ProtoState,
                                      conn_name   = ConnStr}) ->
    case catch ParserFun(Bytes) of
        {more, NewParser}  ->
            noreply(run_socket(State#state{parser_fun = NewParser}));
        {ok, Packet, Rest} ->
            case emqttd_protocol:received(Packet, ProtoState) of
                {ok, ProtoState1} ->
                    received(Rest, State#state{parser_fun = emqttd_parser:new(PacketOpts),
                                                      proto_state = ProtoState1});
                {error, Error} ->
                    lager:error("MQTT protocol error ~p for connection ~p~n", [Error, ConnStr]),
                    stop({shutdown, Error}, State);
                {error, Error, ProtoState1} ->
                    stop({shutdown, Error}, State#state{proto_state = ProtoState1});
                {stop, Reason, ProtoState1} ->
                    stop({shutdown, Reason}, State#state{proto_state = ProtoState1})
            end;
        {error, Error} ->
            lager:error("MQTT detected framing error ~p for connection ~p~n", [ConnStr, Error]),
            stop({shutdown, Error}, State);
        {'EXIT', Reason} ->
            lager:error("received Reason: ~p", [Reason]),
            stop({shutdown, parser_error}, State)
    end.

rate_limit(_Size, State = #state{rate_limit = undefined}) ->
    run_socket(State);
rate_limit(Size, State = #state{rate_limit = Rl}) ->
    case Rl:check(Size) of
        {0, Rl1} ->
            run_socket(State#state{conn_state = running, rate_limit = Rl1});
        {Pause, Rl1} ->
            lager:error("Rate limiter pause for ~p", [Pause]),
            erlang:send_after(Pause, self(), activate_sock),
            State#state{conn_state = blocked, rate_limit = Rl1}
    end.    

run_socket(State = #state{conn_state = blocked}) ->
    State;
run_socket(State = #state{await_recv = true}) ->
    State;
run_socket(State = #state{connection = Connection}) ->
    Connection:async_recv(0, infinity),
    State#state{await_recv = true}.    

noreply(State) ->
    {noreply, State}.    

shutdown(Reason, State) ->
    stop({shutdown, Reason}, State).    

stop(Reason, State) ->
    {stop, Reason, State}.

% ===================================================================================================
%                   以下是休眠这块的函数。
%                   如果用户进程在一定的时间内没有收到除心跳包之外的消息，那么直接休眠
% ===================================================================================================
get_hibernate_state(State) ->
    case check_should_hibernate() of
        true ->
            clear_hibernate(),
            {noreply, State, hibernate};
        _NoHibernate ->
            clear_hibernate(),
            {noreply, State}
    end.

% -------------------------------------------------------------------------
%   设置下次不休眠
% -------------------------------------------------------------------------
no_hibernate() ->
    put( ?HIBERNATE_KEY, true).

% -------------------------------------------------------------------------
%   清除休眠标记
% -------------------------------------------------------------------------
clear_hibernate() ->
    put( ?HIBERNATE_KEY, undefined).

% -------------------------------------------------------------------------
%    判断下次是否需要休眠
% -------------------------------------------------------------------------
check_should_hibernate() ->
    case get( ?HIBERNATE_KEY ) of
        undefined ->
            true;
        _NotUndefined ->
            false
    end.
