-module(emqttd_ack_save_svc).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([ check_timeout/2 ]).

-record(state, {}).

-define(ACK_SAVE_TIMEOUT,   30 ).    % 暂定为 30s，对 ack 表进行一次扫描

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

timer_interval() ->
    erlang:send_after(?ACK_SAVE_TIMEOUT * 1000, self(), { timer_interval } ).

init([]) ->
    timer_interval(),
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info( { timer_interval }, State ) ->
    try
        NowTime = util:unixtime(),
        Fun = fun( { Uid, _Set, LTime }, _AccList ) ->
            case check_timeout( NowTime, LTime ) of
                true ->
                    emqttd_am:save_ack( Uid );
                _NotTimeOut ->
                    skip
            end
        end,
        ets:foldl( Fun, ok, emqttd_am:table() )
    catch
        _M:_R ->
            skip
    end,
    timer_interval(),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

check_timeout( NowTime, OldTime) ->
    abs( NowTime - OldTime ) >= ?ACK_SAVE_TIMEOUT.


