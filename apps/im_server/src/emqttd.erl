%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd main module.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd).

-export([start/0, open/1, is_running/1, env/2]).

-define(MQTT_SOCKOPTS, [
	binary,
	{packet,    raw},
	{reuseaddr, true},
    {reuseport, true},
	{backlog,   512},
	{nodelay,   true}
]).

-type listener() :: {atom(), inet:port_number(), [esockd:option()]}. 

%%------------------------------------------------------------------------------
%% @doc
%% Start emqttd application.
%%
%% @end
%%------------------------------------------------------------------------------
-spec start() -> ok | {error, any()}.
start() ->
    application:start(emqttd).

-spec open([listener()] | listener()) -> any().
open(Listeners) when is_list(Listeners) ->
    [open(Listener) || Listener <- Listeners];

%% open mqtt port
open({mqtt, Port, Options}) ->
    open(mqtt, Port, Options);

%% open mqtt(SSL) port
open({mqtts, Port, Options}) ->
    open(mqtts, Port, Options);

%% open http port
open({http, Port, Options}) ->
    MFArgs = {emqttd_http, handle_request, []},
	mochiweb:start_http(Port, Options, MFArgs);

open({https, Port, Options}) ->
    MFArgs = {emqttd_http, handle_request, []},
    mochiweb:start_http(Port, Options, MFArgs).    

open(Protocol, Port, Options) ->
    {ok, PktOpts} = application:get_env(emqttd, packet),
    {ok, CliOpts} = application:get_env(emqttd, client),
    MFArgs = {emqttd_client, start_link, [[{packet, PktOpts}, {client, CliOpts}]]},
    esockd:open(Protocol, Port, merge(?MQTT_SOCKOPTS, Options) , MFArgs).

is_running(Node) ->
    case rpc:call(Node, erlang, whereis, [emqttd]) of
        {badrpc, _}          -> false;
        undefined            -> false;
        Pid when is_pid(Pid) -> true
    end.

merge(Defaults, Options) ->
    lists:foldl(
        fun({Opt, Val}, Acc) ->
                case lists:keymember(Opt, 1, Acc) of
                    true ->
                        lists:keyreplace(Opt, 1, Acc, {Opt, Val});
                    false ->
                        [{Opt, Val}|Acc]
                end;
            (Opt, Acc) ->
                case lists:member(Opt, Acc) of
                    true -> Acc;
                    false -> [Opt | Acc]
                end
        end, Defaults, Options).

%%------------------------------------------------------------------------------
%% @doc Get environment
%% @end
%%------------------------------------------------------------------------------
-spec env(atom()) -> list().
env(Group) ->
    application:get_env(emqttd, Group, []).

-spec env(atom(), atom()) -> undefined | any().
env(Group, Name) ->
    proplists:get_value(Name, env(Group)).    