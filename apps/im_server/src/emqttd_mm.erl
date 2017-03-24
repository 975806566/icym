%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd off message.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module (emqttd_mm).

-include("emqttd.hrl").
-include("emqttd_packet.hrl").
-behaviour(gen_server).

%% API Exports 
-export([start_link/1, pool/0]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([ insert_pgk_msg_id/3, clear_user_map/1, off_ack/2, route_client/2 ]).

-record(state, {id}).

-define(MM_POOL, mm_pool).

-define(OFF_MSG_lIMIT, 500).

-define(SERVER, ?MODULE).

%%%=============================================================================
%%% API
%%%=============================================================================
pool()  -> ?MM_POOL.    

clear_user_map( UserId ) ->
    CmPid = gproc_pool:pick_worker( ?MM_POOL, UserId ),
    gen_server:cast( CmPid, { user_exit, UserId } ).

insert_pgk_msg_id(UserId, PackageId, MsgId) ->
    CmPid = gproc_pool:pick_worker( ?MM_POOL, UserId ),
    gen_server:cast( CmPid, {insert,UserId, PackageId, MsgId }).

off_ack( UserId, PackageId ) ->
    CmPid = gproc_pool:pick_worker( ?MM_POOL, UserId ),
    gen_server:cast( CmPid, {off_ack, UserId, PackageId}).


%%------------------------------------------------------------------------------
%% @doc Start Ack manager
%% @end
%%------------------------------------------------------------------------------
start_link(Id) ->
    gen_server:start_link(?MODULE, [Id], []).

route_client( UserId, OffMsgList ) ->
    case emqttd_cm:lookup( UserId ) of
        undefined ->
            skip;
        Pid ->
            gen_server:cast(Pid, {route_offmsg, OffMsgList})
    end.

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([Id]) ->
    gproc_pool:connect_worker(?MM_POOL, {?MODULE, Id}),
    Tab = ets:new(tab ,[ set, private ]),
    put( tab, Tab ),
    {ok, #state{id = Id}}.

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast( { off_ack, UserId, PackageId } , State ) ->
    case ets:lookup( get(tab), UserId ) of
        [] ->
            skip;
        [{_UserId, OldMap}] ->
            case maps:get( PackageId, OldMap, undefined ) of
                undefined ->
                    skip;
                MsgId ->
                    off_msg_api: im_ack( MsgId, UserId ),
                    ets:insert( get(tab), {UserId, maps:remove( PackageId, OldMap) })
            end
    end,
    {noreply, State};
handle_cast( { user_exit, UserId } , State ) ->
    ets:delete(get(tab), UserId ),
    {noreply, State};
handle_cast( {insert, UserId, PackageId, MsgId }, State ) ->
    case ets:lookup( get(tab), UserId ) of
        [] ->
            ets:insert(get(tab), {UserId, maps:put( PackageId, MsgId, #{})} );
        [{ UserId, OldMap}] ->
            NewMap = maps:put( PackageId, MsgId, OldMap ),
            ets:insert(get(tab),  {UserId, NewMap} )
    end,
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{id = Id}) ->
    gproc_pool:disconnect_worker(?MM_POOL, {?MODULE, Id}), ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

