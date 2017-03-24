%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd control commands.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_ctl).

-define(PRINT_MSG(Msg), io:format(Msg)).

-define(PRINT(Format, Args), 
    io:format(Format, Args)).

-export([status/1,
         listeners/1]).


status([]) ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
    ?PRINT("Node ~p is ~p~n", [node(), InternalStatus]),
    case lists:keysearch(emqttd, 1, application:which_applications()) of
	false ->
		?PRINT_MSG("emqttd is not running~n");
	{value,_Version} ->
		?PRINT_MSG("emqttd is running~n")
    end.

    
    
listeners([]) ->
    lists:foreach(fun({{Protocol, Port}, Pid}) ->
                ?PRINT("listener ~s:~p~n", [Protocol, Port]), 
                ?PRINT("  acceptors: ~p~n", [esockd:get_acceptors(Pid)]),
                ?PRINT("  max_clients: ~p~n", [esockd:get_max_clients(Pid)]),
                ?PRINT("  current_clients: ~p~n", [esockd:get_current_clients(Pid)])
        end, esockd:listeners()).