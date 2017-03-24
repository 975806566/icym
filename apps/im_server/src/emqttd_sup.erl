%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_sup).

-include("emqttd.hrl").

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/1, start_child/2]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%%%=============================================================================
%%% API
%%%=============================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(ChildSpec) when is_tuple(ChildSpec) ->
	supervisor:start_child(?MODULE, ChildSpec).

%%
%% start_child(Mod::atom(), Type::type()) -> {ok, pid()}
%% @type type() = worker | supervisor
%%
start_child(Mod, Type) when is_atom(Mod) and is_atom(Type) ->
	supervisor:start_child(?MODULE, ?CHILD(Mod, Type)).

%%%=============================================================================
%%% Supervisor callbacks
%%%=============================================================================

init([]) ->
    {ok, {{one_for_all, 10, 100}, []}}.

