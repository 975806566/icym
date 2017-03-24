%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd http publish API and websocket client.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_http).

-import(proplists, [get_value/2, get_value/3]).

-export([handle_request/1]).

handle_request(Req) ->
    handle_request(Req:get(method), Req:get(path), Req).
%%------------------------------------------------------------------------------
%% MQTT Over WebSocket
%%------------------------------------------------------------------------------
handle_request('GET', "/", Req) ->
    lager:info("Websocket Connection from: ~s", [Req:get(peer)]),
    Upgrade = Req:get_header_value("Upgrade"),
    Proto = Req:get_header_value("Sec-WebSocket-Protocol"),
    case {is_websocket(Upgrade), Proto} of
        {true, "mqtt" ++ _Vsn} ->
            emqttd_ws_client:start_link(Req);
        {false, _} ->
            lager:error("Not WebSocket: Upgrade = ~s", [Upgrade]),
            Req:respond({400, [], <<"Bad Request">>});
        {_, Proto} ->
            lager:error("WebSocket with error Protocol: ~s", [Proto]),
            Req:respond({400, [], <<"Bad WebSocket Protocol">>})
    end;

handle_request(Method, Path, Req) ->
    lager:error("Unexpected HTTP Request: ~s ~s connection from:~s", [Method, Path, Req:get(peer)]),
    Req:not_found().    

is_websocket(Upgrade) -> 
    Upgrade =/= undefined andalso string:to_lower(Upgrade) =:= "websocket".