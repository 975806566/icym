%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd websocket client.
%%%
%%% @end
%%%-----------------------------------------------------------------------------

-module(emqttd_ws_client).

-include("emqttd_packet.hrl").
-include("emqttd.hrl").

-behaviour(gen_server).

%% API Exports
-export([start_link/1, ws_loop/3]).


%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% WebSocket loop state
-record(wsocket_state, {request, client_pid, packet_opts, parser_fun}).

%% Client state
-record(state, {ws_pid, request, proto_state, keepalive, sendfun, packet_id, peer_name, sub_list}).

-define(LENGTH, 10).

%%------------------------------------------------------------------------------
%% @doc Start WebSocket client.
%% @end
%%------------------------------------------------------------------------------
start_link(Req) ->
    PktOpts = application:get_env(emqttd, packet, []),
    ParserFun = emqttd_parser:new(PktOpts),
    {ReentryWs, ReplyChannel} = upgrade(Req),
    Params = [self(), Req, ReplyChannel, PktOpts],
    {ok, ClientPid} = gen_server:start_link(?MODULE, Params, []),
    ReentryWs(#wsocket_state{request      = Req,
                             client_pid   = ClientPid,
                             packet_opts  = PktOpts,
                             parser_fun   = ParserFun}).

%%------------------------------------------------------------------------------
%% @private
%% @doc Start WebSocket client.
%% @end
%%------------------------------------------------------------------------------
upgrade(Req) ->
    mochiweb_websocket:upgrade_connection(Req, fun ?MODULE:ws_loop/3).

%%------------------------------------------------------------------------------
%% @doc WebSocket frame receive loop.
%% @end
%%------------------------------------------------------------------------------
ws_loop(<<>>, State, _ReplyChannel) ->
    State;
ws_loop([<<>>], State, _ReplyChannel) ->
    State;

ws_loop([<<"PING">>], State, _ReplyChannel) ->
    State;    

ws_loop([Data | Tail] = AllData, State = #wsocket_state{
        request = Req, 
        client_pid = ClientPid,
        parser_fun = ParserFun}, ReplyChannel)  when length(AllData) > 1 ->
    Peer = Req:get(peer),
    lager:debug("RECV from ~p(WebSocket): ~p", [Peer, Data]),
    Base64 = iolist_to_binary(Data),
    Data2 = case Req:get(scheme) of
        http ->
            base64:decode(Base64);
        https ->
            Base64
    end,
    case ParserFun(Data2) of
        {more, NewParser} ->
            State#wsocket_state{parser_fun = NewParser};
        {ok, Packet, Rest} ->
            gen_server:cast(ClientPid, {received, Packet}),
            case Rest =:= <<>> of
                true -> 
                    ws_loop(Tail, reset_parser(State), ReplyChannel);
                false ->
                    ws_loop(Rest, reset_parser(State), ReplyChannel)
            end;
        {error, Error} ->
            lager:error("MQTT(WebSocket) detected framing error ~p for connection ~p", [Error, Peer]),
            exit({shutdown, Error})
    end;

ws_loop(Data, State = #wsocket_state{request = Req,
                                     client_pid = ClientPid,
                                     parser_fun = ParserFun}, ReplyChannel) ->
    Peer = Req:get(peer),
    lager:debug("RECV from ~p(WebSocket): ~p", [Peer, Data]),
    Base64 = iolist_to_binary(Data),
    Data2 = case Req:get(scheme) of
        http ->
            base64:decode(Base64);
        https ->
            Base64
    end,
    case ParserFun(Data2) of
    {more, NewParser} ->
        State#wsocket_state{parser_fun = NewParser}; 
    {ok, Packet, Rest} ->
        gen_server:cast(ClientPid, {received, Packet}),
        ws_loop(Rest, reset_parser(State), ReplyChannel);
    {error, Error} ->
        lager:error("MQTT(WebSocket) detected framing error ~p for connection ~p", [Error, Peer]),
        exit({shutdown, Error})
    end.    

reset_parser(State = #wsocket_state{packet_opts = PktOpts}) ->
    State#wsocket_state{parser_fun = emqttd_parser:new(PktOpts)}.

%%%=============================================================================
%%% gen_fsm callbacks
%%%=============================================================================

init([WsPid, Req, ReplyChannel, PktOpts]) ->
    {ok, Peername} = Req:get(peername),
    SendFun = fun(Payload) -> ReplyChannel({binary, Payload}) end,
    Headers = mochiweb_request:get(headers, Req),
    HeadersList = mochiweb_headers:to_list(Headers),
    ProtoState = emqttd_protocol:init(Peername, SendFun,
                                      [{ws_initial_headers, HeadersList} | PktOpts]),
    {ok, #state{ws_pid = WsPid, request = Req, proto_state = ProtoState, 
                sendfun = SendFun, packet_id = 1, peer_name = Peername, sub_list = []}}.


handle_call(Req, From, State) ->
    lager:error("unexpected req: ~p From:~p ~n",[ Req, From ]),
    {noreply, State}.

handle_cast({received, Packet}, #state{proto_state = ProtoState} = State) ->
    lager:debug("RECV from ~p", [Packet]),
    case emqttd_protocol:received(Packet, ProtoState) of
    {ok, ProtoState1} ->
        {noreply, State#state{proto_state = ProtoState1}};
    {error, Error} ->
        lager:error("MQTT protocol error ~p", [Error]),
        stop({shutdown, Error}, State);
    {error, Error, ProtoState1} ->
        lager:error("MQTT Error error ~p", [Error]),
        stop({shutdown, Error}, State#state{proto_state = ProtoState1});
    {stop, Reason, ProtoState1} ->
        lager:error("MQTT Reason error ~p", [Reason]),
        stop({shutdown, Reason}, State#state{proto_state = ProtoState1})
    end;

%%----------------------------------------
%% 用户上线，更新用户登录信息
%%----------------------------------------
handle_cast({update_info, Username}, State) ->
    handle_cast({update_info, Username, undefined}, State);
handle_cast({update_info, Username, PlatformType}, State) ->
    handle_cast({update_info, Username, PlatformType, undefined}, State);
handle_cast({update_info, Username, PlatformType, IOSToken}, State) ->
    emqttd_client_tools:update_info(Username, PlatformType, IOSToken, State#state.peer_name ),
    { noreply, State };
 


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


   
%%----------------------------------------
%% 消息发送 QOS0
%%----------------------------------------
handle_cast({send_msg, ?QOS_0, Topic, Payload}, State) ->
    handle_cast({send_msg, undefined, ?QOS_0, Topic, Payload}, State);
handle_cast({send_msg, _, ?QOS_0, Topic, Payload}, State = #state{sendfun = SendFun}) ->
    NewPacket= ?PUBLISH_PACKET(?QOS_0, Topic, undefined, Payload),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    lager:debug("send_msg QOS0---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
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
    lager:debug("send_msg QOS1 or QOS2---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
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
    { noreply, State#state{ packet_id = PacketId + 1}}; 

%% 添加好友通知消息
handle_cast({notice_add_buddy, Username}, State = #state{sendfun = SendFun}) ->
    Topic = lists:concat([?NOTICE_ADD_BUDDY, "@", binary_to_list(Username)]),
    NewPacket= ?PUBLISH_PACKET(?QOS_0, list_to_binary(Topic), undefined, <<"">>),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    %% 添加await_ack
    lager:debug("notice_add_buddy---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    { noreply, State };

%% 删除好友通知消息
handle_cast({notice_remove_buddy, Username}, State = #state{sendfun = SendFun}) ->
    Topic = lists:concat([?NOTICE_REMOVE_BUDDY, "@", binary_to_list(Username)]),
    NewPacket= ?PUBLISH_PACKET(?QOS_0, list_to_binary(Topic), undefined, <<"">>),
    Data = emqttd_serialiser:serialise(NewPacket),
    SendFun(Data),
    %% 添加await_ack
    lager:debug("notice_remove_buddy---SENT to ~ts", [emqttd_packet:dump(NewPacket)]),
    { noreply, State };

handle_cast(Msg, State) ->
    lager:error(" unexpected handle cast. Msg:~p ~n", [ Msg ]),
    { noreply, State}.

%% 在本节点被他人登录
handle_info({stop, duplicate_id, _NewPid}, #state{proto_state = ProtoState, sendfun = SendFun} = State) ->
    lager:error("Shutdown for duplicate clientid: ~p", [emqttd_protocol:client_id(ProtoState)]),
    NewPacket = ?PUBLISH_PACKET(?QOS_0, <<"sys@kick">>, undefined, <<"Your account is already logged in elsewhere">>),
    emqttd_client_tools:send_message(SendFun, NewPacket, <<"">>, 0, ?QOS_0),
    stop({shutdown, duplicate_id}, State);

%% 在其他节点被他人登录
handle_info({stop, duplicate, Node}, State=#state{proto_state = ProtoState, sendfun = SendFun}) ->
    lager:error("Shutdown for duplicate node:~p, clientid: ~p", [Node, emqttd_protocol:client_id(ProtoState)]),
    NewPacket = ?PUBLISH_PACKET(?QOS_0, ?SYSKICK, undefined, <<"Your account is already logged in elsewhere">>),
    emqttd_client_tools:send_message(SendFun, NewPacket, <<"">>, undefined, ?QOS_0),
    stop({shutdown, duplicate}, State);     

handle_info({keepalive, start, Interval}, State = #state{request = Req}) ->
    lager:debug("Client(WebSocket) ~p: Start KeepAlive with ~p seconds", [Req:get(peer), Interval]),
    Conn = Req:get(connection),
    StatFun = fun() ->
        case Conn:getstat([recv_oct]) of
            {ok, [{recv_oct, RecvOct}]} -> {ok, RecvOct};
            {error, Error}              -> {error, Error}
        end
    end,
    KeepAlive = emqttd_keepalive:start(StatFun, Interval, {keepalive, check}),
    {noreply, State#state{keepalive = KeepAlive}};

handle_info({keepalive, check}, State = #state{request = Req, keepalive = KeepAlive}) ->
    case emqttd_keepalive:check(KeepAlive) of
        {ok, KeepAlive1} ->
            lager:debug("Client(WebSocket) ~p: Keepalive Resumed", [Req:get(peer)]),
            emqttd_client:get_hibernate_state( State#state{keepalive = KeepAlive1} );
        {error, timeout} ->
            lager:debug("Client(WebSocket) ~p: Keepalive Timeout!", [Req:get(peer)]),
        stop({shutdown, keepalive_timeout}, State#state{keepalive = undefined});
        {error, Error} ->
            lager:warning("Keepalive error - ~p", [Error]),
            stop(keepalive_error, State)
    end;

handle_info({'EXIT', WsPid, Reason}, State = #state{ws_pid = WsPid}) ->
    stop(Reason, State);

handle_info(Info, State) ->
    lager:info("unexpected Info: ~p ~n",[ Info ]),
    {noreply, State}.

terminate(Reason, #state{ keepalive = KeepAlive, proto_state = ProtoState, sub_list = SubList}) ->
    emqttd_client_tools:terminate(Reason, KeepAlive, ProtoState, SubList ),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

stop(Reason, State ) ->
    {stop, Reason, State}.

