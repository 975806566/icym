%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd application.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_app).

-define(PRINT_MSG(Msg), io:format(Msg)).

-define(PRINT(Format, Args), io:format(Format, Args)).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, start_servers/0]).

-include("emqttd.hrl").
%%%=============================================================================
%%% Application callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%------------------------------------------------------------------------------
-spec start(StartType, StartArgs) -> {ok, pid()} | {ok, pid(), State} | {error, Reason} when 
    StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: term(),
    State     :: term(),
    Reason    :: term().
start(_StartType, _StartArgs) ->
    {ok, Cluster} = application:get_env(cluster),
    schema_db:mnesia_init(Cluster),
    mnesia:change_table_copy_type( schema, node(), disc_copies ),
    print_banner(),
    {ok, Sup} = emqttd_sup:start_link(),
    start_servers(Sup),
    {ok, Listeners} = application:get_env(listen),
    emqttd:open(Listeners),
    register(emqttd, self()),
    checkout_node(),
    print_vsn(),
    reloader:start(),
    recompiler:start(),
    {ok, Sup}.

print_banner() ->
    ?PRINT("starting emqttd on node '~s'~n", [node()]).

print_vsn() ->
    {ok, Vsn} = application:get_key(vsn),
    {ok, Desc} = application:get_key(description),
    ?PRINT("~s ~s is running now~n", [Desc, Vsn]).

checkout_node() ->
    case mnesia_tools:get_node_id() of
        [] ->
            mnesia_tools:dirty_write(nodes, #nodes{id = mnesia_tools:get_next_node_id(), node = node()});
        _ -> ok
    end.

start_servers(Sup) ->
%    {ok, EredisOpts} = application:get_env(eredis),
    {ok, Cluster}    = application:get_env(cluster),
    % {ok, Length}     = application:get_env(off_msg_length),
    {ok, Apn}        = application:get_env(apn_server),
    {ok, Node}       = application:get_env(log_server),
    {ok, Ham}        = application:get_env(ham_server),
    {ok, NoLoginRate } = application:get_env( mem_no_login_rate ),
    {ok, NoServerRate} = application:get_env( mem_no_server_rate ),
    lists:foreach(
        fun({Name, F}) when is_function(F) ->
            ?PRINT("~s is starting...~n", [Name]),
            F(),
            ?PRINT_MSG("[done]~n");
           ({Name, Server}) ->
            ?PRINT("~s is starting...~n", [Name]),
            start_child(Sup, Server),
            ?PRINT_MSG("[done]~n");
           ({Name, Server, Opts}) ->
            ?PRINT("~s is starting...~n", [ Name]),
            start_child(Sup, Server, Opts),
            ?PRINT_MSG("[done]~n")
        end,
        [{"emqttd client manager", emqttd_cm_sup},
         {"emqttd message manager", emqttd_mm_sup},
         {"emqttd pubsub", emqttd_pubsub},
         {"emqttd monitor", monitor, {Cluster, []}},
         % {"emqttd eredis", et_eredis, EredisOpts},
         % {"emqttd collector", emqttd_collector, ServerOpts},
         {"mem_monitor", emqttd_mem_monitor, [ NoLoginRate, NoServerRate ]},
         {"emqttd http active messenger manager",emqttd_ham_sup},
         {"emqttd puback manager",emqttd_am_sup},
         % {"emqttd state subscribe manager",emqttd_ssm_sup},
         {"cluster manager", cluster_manager, Cluster},
         {"emqttd core ets",emqttd_core_ets, [Apn, Node, Ham]}
        ]),
        erlang:system_monitor(whereis(dets),[{large_heap,120000}]).

start_child(Sup, {supervisor, Name}) ->
    supervisor:start_child(Sup, supervisor_spec(Name));
start_child(Sup, Name) when is_atom(Name) ->
    {ok, _ChiId} = supervisor:start_child(Sup, worker_spec(Name)).

start_child(Sup, {supervisor, Name}, Opts) ->
    supervisor:start_child(Sup, supervisor_spec(Name, Opts));
start_child(Sup, Name, Opts) when is_atom(Name) ->
    {ok, _ChiId} = supervisor:start_child(Sup, worker_spec(Name, Opts)).

%%TODO: refactor...
supervisor_spec(Name) ->
    {Name,
        {Name, start_link, []},
            permanent, infinity, supervisor, [Name]}.

supervisor_spec(Name, Opts) ->
    {Name,
        {Name, start_link, [Opts]},
            permanent, infinity, supervisor, [Name]}.

worker_spec(Name) ->
    {Name,
        {Name, start_link, []},
            permanent, 5000, worker, [Name]}.
worker_spec(Name, Opts) -> 
    {Name,
        {Name, start_link, [Opts]},
            permanent, 5000, worker, [Name]}.

%%------------------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec stop(State :: term()) -> term().
stop(_State) ->
    % mnesia:stop(),
    ok.
start_servers() ->
    Sup = erlang:whereis(emqttd_sup),
    case erlang:is_pid(Sup) of
        true ->
            {ok, Ham} = application:get_env(emqttd, ham_server),
            lists:foreach(
                fun({Name, F}) when is_function(F) ->
                    ?PRINT("~s is starting...~n", [Name]),
                    F(),
                    ?PRINT_MSG("[done]~n");
                   ({Name, Server}) ->
                    ?PRINT("~s is starting...~n", [Name]),
                    start_child(Sup, Server),
                    ?PRINT_MSG("[done]~n");
                   ({Name, Server, Opts}) ->
                    ?PRINT("~s is starting...~n", [ Name]),
                    start_child(Sup, Server, Opts),
                    ?PRINT_MSG("[done]~n")
                end,
                [{"emqttd rpc manager",emqttd_ham_sup, Ham}]);
        false ->
            lager:error("Not find emqttd_sup process")
    end.

