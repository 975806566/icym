%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd client manager supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_cm_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ets:new(emqttd_cm:table(), [set, named_table, public, {keypos, 2},
                                {write_concurrency, true}]),
    Schedulers = erlang:system_info(schedulers),
    gproc_pool:new(emqttd_cm:pool(), hash, [{size, Schedulers}]),
    Children = lists:map(
                 fun(I) ->
                    Name = {emqttd_cm, I},
                    gproc_pool:add_worker(emqttd_cm:pool(), Name, I),
                    {Name, {emqttd_cm, start_link, [I]},
                                permanent, 10000, worker, [emqttd_cm]}
                 end, lists:seq(1, Schedulers)),
    {ok, {{one_for_all, 10, 100}, Children}}.


