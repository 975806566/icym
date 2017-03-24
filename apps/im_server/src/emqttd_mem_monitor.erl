% ----------------------------------------------------------------------
% @author chenyiming
% @doc 用于监控总的服务器已经使用的内存。
% ----------------------------------------------------------------------

-module(emqttd_mem_monitor).

-behaviour(gen_server).

%% API functions
-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {}).

-define(TIMER_INTERVAL,         5 * 1000).  % 5秒更新一次内存使用率
-define(DEFAULT_LOGIN_RATE,     70).        % 默认情况下，内存使用超过 70% 不再允许新的用户登录
-define(DEFAULT_NO_SERVER_RATE, 80).        % 默认情况下， 内存使用率超过 80% 不再进行服务

start_link( Args ) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

% ----------------------------------------------------------------
% NoLoginRate::  不允许登录的内存使用率，默认是 70%
% NoServerRate:: 不再服务的内存使用率    默认是 80%   
% ----------------------------------------------------------------
init([ NoLoginRate0, NoServerRate0 ]) ->
    { NoLoginRate, NoServerRate } =
    case NoLoginRate0 >= 0 andalso 
         NoLoginRate0 =< 100 andalso 
         NoServerRate0 >= 0 andalso 
         NoServerRate0 =< 100 of
        true ->
            { NoLoginRate0, NoServerRate0 };
        _NotInRange ->
            lager:error("config error. NoLoginRate:~p NoServerRate:~p ~n",[ NoLoginRate0, NoServerRate0 ]),
            { ?DEFAULT_LOGIN_RATE, ?DEFAULT_NO_SERVER_RATE }
    end,

    application:ensure_all_started( os_mon ),
    util:set_kv( mem_used, 0 ),
    util:set_kv( mem_no_login_rate,     NoLoginRate ),
    util:set_kv( mem_no_server_rate,    NoServerRate ),

    util:set_kv( mem_rate_can_login,    true ),
    util:set_kv( mem_rate_can_serve,    true ),       
    timer_interval(),
    {ok, #state{}}.

timer_interval( ) ->
    erlang:send_after( ?TIMER_INTERVAL, self(), { timer_interval }).

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

do_count_mem_rate(  ) ->
    try
        MemDataList = memsup:get_system_memory_data() ,
        Total = proplists:get_value( total_memory, MemDataList ),
        Buffered = proplists:get_value( buffered_memory, MemDataList ), 
        Cached = proplists:get_value( cached_memory, MemDataList ), 
        Free = proplists:get_value( free_memory, MemDataList ), 
        UsedRate = trunc((Total - Buffered - Cached - Free ) * 100 / Total ),
        NoLoginRate = util:get_value( mem_no_login_rate, ?DEFAULT_LOGIN_RATE ),
        NoServerRate = util:get_value( mem_no_server_rate, ?DEFAULT_NO_SERVER_RATE ),

        util:set_kv( mem_used, UsedRate ),

%        util:print(" Total:~p Buffered:~p Cached:~p [Free:~p] [FreeAll:~p]~n", [ Total, Buffered, Cached, Free, Buffered + Cached + Free ]),
%        util:print("MemDataList:~p UsedRate: ~p ~n", [ MemDataList, UsedRate ]),

        % 更新是否登录新用户字段的值
        case UsedRate >= NoLoginRate of
            true ->
                lager:error("mem cant login NowMem:~p NoLoginMem:~p~n", [ UsedRate, NoLoginRate ]),
                util:set_kv( mem_rate_can_login, false );
            false ->
                util:set_kv( mem_rate_can_login, true )
        end,
        
        % 更新是否允许继续服务字段
        case UsedRate >= NoServerRate of
            true ->
                lager:error("mem cant server NowMem:~p NoServerMem:~p~n", [ UsedRate,NoServerRate ]),
                util:set_kv( mem_rate_can_serve,    false );
            false ->
                util:set_kv( mem_rate_can_serve,    true )
        end
    catch
        M:R ->
            lager:error( "~p count_mem_rate error M:~p R:~p ~p ~n",[?MODULE, M, R,erlang:get_stacktrace()  ] )
    end.

handle_info ( { timer_interval }, State) ->
    timer_interval(),
    do_count_mem_rate(),
    {noreply, State};
    
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

