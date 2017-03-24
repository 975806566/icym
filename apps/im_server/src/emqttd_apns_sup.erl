%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for ios apns supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_apns_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

start_link(Apns) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Apns]).

init([Apns]) ->
    %%ets:new(emqttd_apns:table(), [set, named_table, public, {keypos, 1}]),
    Schedulers = erlang:system_info(schedulers),
    gproc_pool:new(emqttd_apns:pool(), hash, [{size, Schedulers}]),
    Children = lists:map(
                 fun(I) ->
                    Name = {emqttd_apns, I},
                    gproc_pool:add_worker(emqttd_apns:pool(), Name, I),
                    {Name, {emqttd_apns, start_link, [I, Apns]},
                                permanent, 10000, worker, [emqttd_apns]}
                 end, lists:seq(1, Schedulers)),
    {ok, {{one_for_all, 10, 100}, Children}}.


