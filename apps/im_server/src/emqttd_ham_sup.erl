%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd for http active messenger supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_ham_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/1, start_child/2]).

%% Supervisor callbacks
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {{one_for_all, 10, 100}, []}}.

start_child(Name) when is_atom(Name) ->
    supervisor:start_child(emqttd_ham_sup, worker_spec(Name)).

start_child(Name, Opts) when is_atom(Name) ->
    supervisor:start_child(emqttd_ham_sup, worker_spec(Name, Opts)).


worker_spec(Name) ->
    {Name, {emqttd_ham, start_link, [Name]}, permanent, 5000, worker, [Name]}.
worker_spec(Name, Opts) -> 
    {Name, {emqttd_ham, start_link, [Name, Opts]}, permanent, 5000, worker, [Name]}.



