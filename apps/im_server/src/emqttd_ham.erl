%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for http active messenger.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module (emqttd_ham).

-behaviour(gen_server).

-include("emqttd.hrl").

-include("emqttd_packet.hrl").

-define(SERVER, ?MODULE).

%% API Exports 
-export([start_link/1, send_msg_ham/6, send_group_ham/6, to_msg_ham/5, to_group_ham/4, dispatch/6, send_sub_state/4, to_sub_state/3]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([ to_msg_ham_list/5 ]).

-record(state, {}).

%%%=============================================================================
%%% API
%%%=============================================================================
%% 发送点对点消息
send_msg_ham(Appkey, FromUsername, Username, MsgType, Payload, Qos) ->
    Pid = get_process(Username),
    gen_server:cast(Pid, {send_msg_ham, Appkey, FromUsername, Username, MsgType, Payload, Qos}).
    
%% 发送群消息
send_group_ham(Appkey, FromUsername, Username, GroupId, Payload, Qos) ->
    Pid = get_process(Username),
    gen_server:cast(Pid, {send_group_ham, Appkey, FromUsername, Username, GroupId, Payload, Qos}).
    
%% 发送用户上下线消息
send_sub_state(Appkey, FromUsername, Username, Type) ->
    Pid = get_process(Username),
    gen_server:cast(Pid, {send_sub_state, Appkey, FromUsername, Username, Type}).

to_msg_ham_list( FromUsername, ToUsernameList, _PacketId, MsgType, Payload ) ->
    util:print( "toUserNameList: ~p", [ ToUsernameList ]),
    Type = case MsgType of
        1 -> chat;
        2 -> sfile
    end,
    [ emqttd_route:do_route_to_uid( 1, Payload, Type, Uid, FromUsername )  || Uid <- ToUsernameList ].
    

%% 接收点对点消息
to_msg_ham(FromUsername, Username, _PacketId, MsgType, Payload) ->
    Type = case MsgType of
        1 -> chat;
        2 -> sfile
    end,
    util:print(" to msg ham ~p ~p ~p ~p ~p~n", [ FromUsername, Username, _PacketId, MsgType, Payload ]),
    emqttd_route:do_route_to_uid(1, Payload, Type, Username,  FromUsername ).


%% 接收群消息
to_group_ham(FromUsername, GroupId, PacketId, Payload) ->
    NewPacket = #mqtt_message{qos = 1,  msgid = PacketId, topic = GroupId,payload = Payload},
    emqttd_pubsub:publish(NewPacket, FromUsername),
    emqttd_client_tools:msg_info(FromUsername, GroupId, Payload, publish).  

%% 接收用户上下线消息
to_sub_state(FromUsername, UsernameList, Type) ->
    lists:foreach(
        fun(Username) ->
            case Type of
                0 ->
                    case mnesia_tools:dirty_read(users, Username) of
                        [] -> 
                            lager:error("Username:~p not exist~n", [Username]);
                        [_User] ->
                            emqttd_ssm:state_unsubscribe(FromUsername, Username)
                    end;
                1 ->
                    case mnesia_tools:dirty_read(users, Username) of
                        [] -> 
                            lager:error("Username:~p not exist~n", [Username]);
                        [_User] ->
                            emqttd_ssm:state_subscribe(FromUsername, Username)
                    end
                    
            end
        end, UsernameList).

dispatch(Username, Payload, Topic, Content, Nickname, PacketId) ->
    Pid = emqttd_cm:lookup(Username),
    case Pid of
        undefined ->
            emqttd_mm:insert_off_msg(Username, Payload, Topic, 1, PacketId, Content, Nickname);
        _ ->
            gen_server:cast(Pid, {send_msg, Username, 1, Topic, Payload})
    end.          

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

    
%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([]) ->
    {ok, #state{}}.

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast({send_msg_ham, Appkey, FromUsername, Username, MsgType, Payload, Qos}, State) ->
    case emqttd_core_ets:lookup_node(application:get_env(emqttd, ham_server, undefined)) of
        undefined ->
            %lager:error("Not find ham_server node"),
            ok;
        Node ->
            rpc:cast(Node, ham_server_core, send_msg_ham, [Appkey, FromUsername, Username, MsgType, Payload, Qos])
    end,
    hibernate(State);

handle_cast({send_group_ham, Appkey, FromUsername, Username, GroupId, Payload, Qos}, State) ->
    case emqttd_core_ets:lookup_node(application:get_env(emqttd, ham_server, undefined)) of
        undefined ->
            %lager:error("Not find ham_server node"),
            ok;
        Node ->
            rpc:cast(Node, ham_server_core, send_group_ham, [Appkey, FromUsername, Username, GroupId, Payload, Qos])
    end,
    hibernate(State);

handle_cast({send_sub_state, Appkey, FromUsername, Username, Type}, State) ->
    case emqttd_core_ets:lookup_node(application:get_env(emqttd, ham_server, undefined)) of
        undefined ->
            %lager:error("Not find ham_server node"),
            ok;
        Node ->
            rpc:cast(Node, ham_server_core, send_sub_state, [Appkey, FromUsername, Username, Type])
    end,
    hibernate(State);

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

get_process(Username) when is_binary(Username) ->
    HamPidName = list_to_atom(lists:concat(["emqttd_ham_", binary_to_list(Username)])),
    case whereis(HamPidName) of
        undefined ->
            case emqttd_ham_sup:start_child(HamPidName) of
                {ok, Pid} ->
                    Pid;
                {error,{already_started, Pid1}}->
                    Pid1;
                Error ->
                    lager:error("create emqttd_ham process fial. error:~p", [Error])
            end;
        HamPid ->
            case erlang:process_info(HamPid, message_queue_len) of
                undefined ->
                    lager:error("Pid is message_queue_len undefined~p~n", [HamPid]);
                {_, Length} ->
                    case Length > 50000 of
                        true  -> undefined;
                        false -> HamPid
                    end;
                Error ->
                    lager:error("Error is message_queue_len error~p~n", [Error])
            end
    end;

get_process(Username) ->
    lager:error("Username type error:~p", [Username]),
    undefined.

hibernate(State) ->
    {noreply, State, hibernate}.
