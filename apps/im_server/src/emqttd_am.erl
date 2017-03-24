%%%-----------------------------------------------------------------------------
%%% @doc
%%% MQTT Ack Manager
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_am).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API Exports 
-export([start_link/1, pool/0, table/0, count/0, count/1]).

-export([awaiting_ack/3, un_awaiting_ack/2, load/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, save_ack/1 ]).

-record(state, {id, tab}).

-define(AM_POOL, am_pool).

-define(ACK_TAB, ack_table).

% -include_lib("eunit/include/eunit.hrl").


%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Start Ack manager
%% @end
%%------------------------------------------------------------------------------
start_link(Id) ->
    gen_server:start_link(?MODULE, [Id], []).

%write_off_timer() ->
%	erlang:send_after( ?ACK_OFFMSG_TIME * 1000, self(), {write_offmsg_timer}).

pool()  -> ?AM_POOL.

table() -> ?ACK_TAB.

count() ->  ets:info(?ACK_TAB, size).

count( Uid ) ->
    case ets:lookup( ?ACK_TAB, Uid ) of
        [] ->
            0;
        [ {Uid, Set, _Time } ] ->
            sets:size( Set )
    end.

% -----------------------------------------------------------------------------
% 通过索引，找到真正的 body 包
% -----------------------------------------------------------------------------
do_get_all_packets(_Uid, [] ) ->
    [];
do_get_all_packets(Uid, PacketIdList ) ->
    Fun = fun( PacketId, AccList ) ->
        case ets:lookup( ack_body, {Uid, PacketId} ) of
            [] ->
                AccList;
            [ {_Key, Packet} ] ->
                ets:delete( ack_body, {Uid, PacketId}),
                [ Packet | AccList ]
        end
    end,
    lists:foldr(Fun, [], PacketIdList ).

load(Uid) ->
    case ets:lookup( ?ACK_TAB, Uid ) of
        [] ->
            [];
        [ {Uid, Set, _Time} ] ->
            ets:delete( ?ACK_TAB, Uid ),
            PacketIdList = lists:sort( sets:to_list( Set ) ),
            do_get_all_packets( Uid, PacketIdList )
    end.

awaiting_ack(Uid, PacketId, Packet) ->
    CmPid = gproc_pool:pick_worker(?AM_POOL, Uid),
    gen_server:cast(CmPid, {awaiting_ack, Uid, PacketId, Packet}).

un_awaiting_ack(Uid, PacketId) ->
    util:print( "[recv_ack] => [Uid:~p, PacketId:~p]~n", [ Uid, PacketId ]),
    emqttd_mm:off_ack( Uid, PacketId ),
    CmPid = gproc_pool:pick_worker(?AM_POOL, Uid),
    gen_server:cast(CmPid, {un_awaiting_ack, Uid, PacketId}).

save_ack( Uid ) ->
    CmPid = gproc_pool:pick_worker(?AM_POOL, Uid),
    gen_server:cast(CmPid, { save_ack, Uid }).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

init([Id]) ->
%    write_off_timer(),
    gproc_pool:connect_worker(?AM_POOL, {?MODULE, Id}),
    {ok, #state{id = Id}}.

handle_call(Req, _From, State) ->
    lager:error("unexpected request: ~p", [Req]),
    {reply, {error, badreq}, State}.

handle_cast({awaiting_ack, Uid, PacketId, Packet}, State) ->
    NowTime = util:unixtime(),
    NewKey = { Uid, PacketId },
    ets:insert( ack_body, { NewKey, Packet }),
    case ets:lookup( ?ACK_TAB, Uid ) of
        [] ->
            ets:insert( ?ACK_TAB, {Uid, sets:from_list([ PacketId ]),  NowTime});
        [ {_Uid, OldSet, _LastTime} ] ->
            ets:insert( ?ACK_TAB, {Uid, sets:add_element( PacketId, OldSet), NowTime})
    end,
    {noreply, State};

handle_cast({un_awaiting_ack, Uid, PacketId }, State) ->
    NowTime = util:unixtime(),
    ets:delete( ack_body, { Uid, PacketId }),
    case ets:lookup(?ACK_TAB, Uid) of
        [] -> 
            skip;
        [ { Uid, OldSet, _LastUpdateTime } ]  ->
            NewSet = sets:del_element( PacketId, OldSet ),
            case sets:size( NewSet ) of
                0 ->
                    ets:delete( ?ACK_TAB, Uid );
                _NOtNull ->
                    ets:insert( ?ACK_TAB, { Uid, NewSet, NowTime })
            end 
    end,
    {noreply, State};    

handle_cast( { save_ack, Uid }, State) ->
    NowTime = util:unixtime(),
    case ets:lookup( ?ACK_TAB, Uid ) of
        [{ _Uid, _Set, LTime }] ->
            case emqttd_ack_save_svc:check_timeout( NowTime, LTime ) of
                true ->
                    emqttd_client_tools:fail_msg_to_offmsg( Uid );
                _NotTimeOut ->
                    skip
            end;
        _OthersCase ->
            skip
    end,
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{id = Id}) ->
    gproc_pool:disconnect_worker(?AM_POOL, {?MODULE, Id}), ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%do_check_timeout( NowTime, OldTime) ->
%    abs( NowTime - OldTime ) >= ?ACK_OFFMSG_TIME.

%insert_test( ) ->
%    ets:delete_all_objects( ack_table ),
%
%    Uid1 = <<"1">>,
%    PacketId1 = 1,
%    ?assertEqual(0, count( Uid1 ) ),
%    ?assertEqual([], load( Uid1 ) ),

%    awaiting_ack( Uid1, PacketId1, {packet1} ),
%    timer:sleep( 50 ),
%    util:print("count(uid1) ~p ~p~n",[count( Uid1 ), Uid1 ]),
%    ?assertEqual(1, count( Uid1 )),
%    [ {_Uid, _Map, Time_1} ] = ets:lookup( ?ACK_TAB, Uid1 ),
%    List1 = ets:tab2list( ?ACK_TAB ),
%    ?assertEqual([{Uid1, #{1 => {packet1}}, Time_1}], List1),
%    util:print(" ~p ~n",[load( Uid1 )]),
%    ?assertEqual( [{packet1}], load( Uid1) ),
%    un_awaiting_ack( Uid1, PacketId1 ),
%    timer:sleep( 200 ),
%    ?assertEqual(0, count( Uid1 ) ),
%    ?assertEqual([], load( Uid1 ) ),
%    ?assertEqual([], ets:tab2list( ?A0CK_TAB) ),
    
%    PacketId2 = 2,
%    awaiting_ack( Uid1, PacketId1, {packet1} ),
%    awaiting_ack( Uid1, PacketId2, {packet2} ),
%    timer:sleep( 200 ),
%    ?assertEqual(2, count( Uid1 ) ),
%    ?assertEqual( [{packet1},{packet2}], lists:sort( load( Uid1) ) ),
%    un_awaiting_ack( Uid1, PacketId1 ),
%    un_awaiting_ack( Uid1, PacketId2 ),
%    timer:sleep( 200 ),
%    ?assertEqual(0, count( Uid1 ) ),
%    ?assertEqual( [], lists:sort( load( Uid1) ) ),   
%    ok.
    


