%%%-----------------------------------------------------------------------------
%%% @doc
%%% MQTT Client Manager
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_cm).

-include("emqttd.hrl").

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API Exports 
-export([start_link/1, pool/0, table/0, count/0]).

-export([lookup/1, register/1, unregister/1, get_state_for_nodes/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {id, tab}).

-define(CM_POOL, cm_pool).

-define(CLIENT_TAB, mqtt_client).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Start client manager
%% @end
%%------------------------------------------------------------------------------
start_link(Id) ->
    gen_server:start_link(?MODULE, [Id], []).

pool() -> ?CM_POOL.

table() -> ?CLIENT_TAB.

%%------------------------------------------------------------------------------
%% @doc Lookup client pid with clientId
%% @end
%%------------------------------------------------------------------------------
lookup(ClientId) when is_binary(ClientId) ->
    case ets:lookup(?CLIENT_TAB, ClientId) of
    [Client] -> Client#mqtt_client.client_pid;
    [] -> undefined
    end.
get_state_for_nodes(ClientId) when is_binary(ClientId) ->
    Cluster = application:get_env(emqttd, cluster, []),
    StateList = lists:foldl(
        fun({_, Node, Type}, AccIn) ->
            case Type =:= mqtt of
                true ->
                    case Node =/= node() of
                        true ->
                            case emqttd:is_running(Node) of
                                true ->
                                    case rpc:call(Node, ?MODULE, lookup, [ClientId]) of
                                        undefined -> AccIn;
                                        _ -> AccIn ++ [true]
                                    end;
                                false ->
                                    AccIn
                            end;
                        false ->
                            case lookup(ClientId) of
                                undefined -> AccIn;
                                _ -> AccIn ++ [true]
                            end
                    end;
                false ->
                    AccIn
            end
        end, [], Cluster),
    length(StateList) > 0.

count() ->  ets:info(?CLIENT_TAB, size).

%%------------------------------------------------------------------------------
%% @doc Register clientId with pid.
%% @end
%%------------------------------------------------------------------------------
register(#mqtt_client{clientid = ClientId} = Client) ->
    CmPid = gproc_pool:pick_worker(?CM_POOL, ClientId),
    gen_server:call(CmPid, {register, Client}, infinity).

%%------------------------------------------------------------------------------
%% @doc Unregister clientId with pid.
%% @end
%%------------------------------------------------------------------------------
unregister(ClientId) when is_binary(ClientId) ->
    CmPid = gproc_pool:pick_worker(?CM_POOL, ClientId),
    gen_server:cast(CmPid, {unregister, ClientId, self()}).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([Id]) ->
    gproc_pool:connect_worker(?CM_POOL, {?MODULE, Id}),
    {ok, #state{id = Id}}.

handle_call({register, Client = #mqtt_client{clientid = ClientId, client_pid = Pid}}, _From, State) ->
    case ets:lookup(?CLIENT_TAB, ClientId) of
        [#mqtt_client{client_pid = Pid}] ->
            lager:error("clientId '~s' has been registered with ~p", [ClientId, Pid]),
            ignore;
        [#mqtt_client{client_pid = OldPid, client_mon = MRef}] ->
            lager:error("clientId '~s' is duplicated: pid=~p, oldpid=~p", [ClientId, Pid, OldPid]),
            OldPid ! {stop, duplicate_id, Pid},
            erlang:demonitor(MRef),
            ets:insert(?CLIENT_TAB, Client#mqtt_client{client_mon = erlang:monitor(process, Pid)});
        [] -> 
            ets:insert(?CLIENT_TAB, Client#mqtt_client{client_mon = erlang:monitor(process, Pid)})
    end,
    {reply, ok, State};

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast({unregister, ClientId, Pid}, State) ->
    case ets:lookup(?CLIENT_TAB, ClientId) of
    [#mqtt_client{client_pid = Pid, client_mon = MRef}] ->
        erlang:demonitor(MRef, [flush]),
        ets:delete(?CLIENT_TAB, ClientId);
    [_] -> 
        ignore;
    [] ->
        skip
    end,
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', MRef, process, DownPid, Reason}, State) ->
    lager:error("DOWN Reason: ~p", [Reason]),
    case ets:match_object(?CLIENT_TAB, {mqtt_client, '$1', '_', '_', DownPid, MRef, '_', '_'}) of
        [] ->
            ignore;
        Clients ->
            lists:foreach(
                fun(Client = #mqtt_client{clientid = ClientId}) ->
                        ets:delete_object(?CLIENT_TAB, Client),
                        lager:error("Client ~s is Down: ~p", [ClientId, Reason])
                end, Clients)
    end,
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, #state{id = Id}) ->
    lager:error("terminate Reason: ~p", [Reason]),
    gproc_pool:disconnect_worker(?CM_POOL, {?MODULE, Id}), ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


