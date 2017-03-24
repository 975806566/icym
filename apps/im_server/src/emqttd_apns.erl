%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for ios apns.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module (emqttd_apns).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API Exports 
-export([start_link/2, pool/0, send_apns_message/5]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {id, apn_server}).

-define(APNS_POOL, apns_pool).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Start Ack manager
%% @end
%%------------------------------------------------------------------------------
start_link(Id, Apns) ->
    gen_server:start_link(?MODULE, [Id, Apns], []).

pool()  -> ?APNS_POOL.

send_apns_message(_Username, Appkey, ToKen, Message, Count) ->
    case emqttd_core_ets:lookup_node(application:get_env(emqttd, apn_server, undefined)) of
        undefined ->
            lager:error("Not find apn_server node"),
            ok;
        Node ->
            rpc:cast(Node, apn_server_core, call_apn_server, [Appkey, ToKen, Message, Count])
    end.

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([Id, Apns]) ->
    gproc_pool:connect_worker(?APNS_POOL, {?MODULE, Id}),
    case net_adm:ping(Apns) of
        pang ->
            io:format("connect apn server ~p fail~n", [Apns]);
        pong ->
            io:format("connect apn server ~p succeed~n", [Apns])
    end,
    {ok, #state{id = Id, apn_server = Apns}}.

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast({send_apns_message, Appkey, ToKen, Message, Count}, #state{apn_server = Apns} = State) ->
    rpc:cast(Apns, apn_server_core, call_apn_server, [Appkey, ToKen, Message, Count]),
    {noreply, State};


handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{id = Id}) ->
    gproc_pool:disconnect_worker(?APNS_POOL, {?MODULE, Id}), ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.