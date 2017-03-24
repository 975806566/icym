%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for off_message manager supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_mm_sup).

-include("emqttd.hrl").

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Schedulers = erlang:system_info(schedulers),
    gproc_pool:new(emqttd_mm:pool(), hash, [{size, Schedulers}]),
    Children = lists:map(
                 fun(I) ->
                    Name = {emqttd_mm, I},
                    gproc_pool:add_worker(emqttd_mm:pool(), Name, I),
                    {Name, {emqttd_mm, start_link, [I]},
                                permanent, 10000, worker, [emqttd_mm]}
                 end, lists:seq(1, Schedulers)),
    {ok, {{one_for_all, 10, 100}, Children}}.


