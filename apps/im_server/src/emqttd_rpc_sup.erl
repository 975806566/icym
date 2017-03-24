%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for rpc supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_rpc_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

start_link(Node) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Node]).

init([Node]) ->
    Schedulers = erlang:system_info(schedulers),
    gproc_pool:new(emqttd_rpc:pool(), hash, [{size, Schedulers}]),
    Children = lists:map(
                 fun(I) ->
                    Name = {emqttd_rpc, I},
                    gproc_pool:add_worker(emqttd_rpc:pool(), Name, I),
                    {Name, {emqttd_rpc, start_link, [I, Node]},
                                permanent, 10000, worker, [emqttd_rpc]}
                 end, lists:seq(1, Schedulers)),
    {ok, {{one_for_all, 10, 100}, Children}}.


