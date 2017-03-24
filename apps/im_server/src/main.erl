%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd main module.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(main).

%% API
-export([start/0]).
% sasl, syntax_tools, ssl, mnesia, os_mon, inets, goldrush, lager, esockd, mochiweb
start() ->
    Apps = [crypto, sasl, os_mon,asn1, public_key,xmerl, mnesia, syntax_tools, compiler, goldrush, gen_logger, lager, esockd, ssl, inets, mochiweb, gproc, mcast],
    lists:foreach(
        fun(App) ->
            Res = application:start(App),
            io:format("App:~p, status:~p~n", [App, Res])
        end, Apps),
    emqttd:start().
