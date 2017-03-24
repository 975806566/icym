%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for prc.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module (emqttd_rpc).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API Exports 
-export([start_link/2, pool/0, login_info/4, msg_info/4]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {id, node}).

-define(RPC_POOL, rpc_pool).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Start Ack manager
%% @end
%%------------------------------------------------------------------------------
start_link(Id, Node) ->
    gen_server:start_link(?MODULE, [Id, Node], []).

pool()  -> ?RPC_POOL.

login_info(Username, Ip, Tpye, Cause) ->
    Pid = gproc_pool:pick_worker(?RPC_POOL, Username),
    gen_server:cast(Pid, {login_info, Username, Ip, Tpye, Cause}).

msg_info(FromUid, ToUid, Content, Type) ->
    Pid = gproc_pool:pick_worker(?RPC_POOL, FromUid),
    gen_server:cast(Pid, {msg_info, FromUid, ToUid, Content, Type}).
    


%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([Id, Node]) ->
    gproc_pool:connect_worker(?RPC_POOL, {?MODULE, Id}),
    case net_adm:ping(Node) of
        pang ->
            io:format("Connect Node ~p fail~n", [Node]);
        pong ->
            io:format("Connect Node ~p succeed~n", [Node])
    end,
    {ok, #state{id = Id, node = Node}}.

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast({login_info, Username, Ip, Tpye, Cause}, #state{node = Node} = State) ->
    rpc:cast(Node, log_server_core, login_info, [Username, Ip, Tpye, Cause]),
    {noreply, State};

handle_cast({msg_info, FromUid, ToUid, Content, Type}, #state{node = Node} = State) ->
    rpc:cast(Node, log_server_core, msg_info, [FromUid, ToUid, Content, Type]),
    {noreply, State};    


handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{id = Id}) ->
    gproc_pool:disconnect_worker(?RPC_POOL, {?MODULE, Id}), ok.

code_change(OldVsn, State, Extra) ->
    io:format("---~p~n", [{OldVsn, State, Extra}]),
    {ok, State}.


