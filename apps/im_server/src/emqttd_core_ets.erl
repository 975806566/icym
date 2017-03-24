%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd core ets
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module (emqttd_core_ets).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API Exports 
-export([start_link/1, lookup_node/1]).


%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {}).

%%%=============================================================================
%%% API
%%%=============================================================================
lookup_node(NodeName) when is_atom(NodeName) ->
    case lists:member(NodeName, nodes()) of
        true -> NodeName;
        false -> undefined
    end;
lookup_node(NodeName) ->
    lager:error("Error NodeName:~p type", [NodeName]),
    undefined.
%%------------------------------------------------------------------------------
%% @doc Start core ets
%% @end
%%------------------------------------------------------------------------------
start_link(Nodes) ->
    gen_server:start_link(?MODULE, [Nodes], []).

    
%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================    
init([Nodes]) ->
    lists:foreach(
        fun(Node) ->
            case net_adm:ping(Node) of
                pang ->
                    lager:debug("Connect Node ~p fail~n", [Node]);
                pong ->
                    io:format("Connect Node ~p succeed~n", [Node])
            end
        end, Nodes),
    {ok, #state{}}.

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.     

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{}) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
