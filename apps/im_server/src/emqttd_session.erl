-module(emqttd_session).

-behaviour(gen_server2).

%% Session API
-export([ start_link/1, router/6 ]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {}).

start_link( CleanSess ) ->
    gen_server2:start_link(?MODULE, [ CleanSess ], []).

router(SessPid, Packet, Topic, Payload, Username, SendFun) ->
    gen_server2:cast(SessPid, {router, Packet, Topic, Payload, Username, SendFun, self() }).


%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

init([ CleanSess ]) ->
    put( clean_sess, CleanSess ),
    process_flag(trap_exit, true),
    {ok, #state{}, hibernate}.

handle_call(_Req, _From, State) ->
    {repay, ok, State, hibernate}.

handle_cast({router, Packet, Topic, Payload, Username, SendFun, SelfPid }, State) ->
    case util:get_value( mem_rate_can_serve, true ) of
        true ->
            emqttd_route:route(Packet, Topic, Payload, Username, SendFun, SelfPid );
        _MemFull ->
            skip
    end,
    hibernate(State);

handle_cast(_Msg, State) ->
    hibernate(State).

handle_info(close, State) ->
    {stop, normal, State};
    
handle_info(_Info, State) ->
    hibernate(State).

terminate(_Reason, _State) -> 
    ok.

code_change(_OldVsn, Session, _Extra) ->
    {ok, Session}.

hibernate(State) ->
    {noreply, State, hibernate}.
