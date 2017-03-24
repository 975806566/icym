%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd ack manager supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_am_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

% --------------------------------------------------------------------------------------------
% @doc ack_table 只存储索引， ack_body 才会存储真正的实体
% --------------------------------------------------------------------------------------------
init([]) ->
    % ----------------------
    % 存储 ack 索引
    % ----------------------
    ets:new(emqttd_am:table(), [set, named_table, public, {keypos, 1}, {write_concurrency, true}]),
    
    % ----------------------
    % 存储 ack 实体
    % ----------------------
    ets:new(ack_body,   [set, named_table, public, {write_concurrency, true}] ),
    Schedulers = erlang:system_info(schedulers),
    gproc_pool:new(emqttd_am:pool(), hash, [{size, Schedulers}]),
    Children = lists:map(
                 fun(I) ->
                    Name = {emqttd_am, I},
                    gproc_pool:add_worker(emqttd_am:pool(), Name, I),
                    {Name, {emqttd_am, start_link, [I]},
                                permanent, 10000, worker, [emqttd_am]}
                 end, lists:seq(1, Schedulers)),

    AckSaveSvc = { emqttd_ack_save_svc, 
                   {emqttd_ack_save_svc, start_link, []},
                   permanent, 
                   10000, 
                   worker, 
                   [ emqttd_ack_save_svc ]},
    ChildrenList = [AckSaveSvc | Children],
    {ok, {{one_for_all, 10, 100}, ChildrenList }}.


