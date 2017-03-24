%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd tools.
%%%
%%% @end
%%%-----------------------------------------------------------------------------

-module(emqttd_tools).

%% API
-export([get_unixtime/0,sort/2, get_token/1, get_today_over_second/0]).

get_unixtime() ->
    {M, S, _} = os:timestamp(),
    Time = M * 1000000 + S,
    integer_to_list(Time).


%% 获取当天剩余的秒数
get_today_over_second() ->
  Now = list_to_integer(get_unixtime()),
  (Now-((Now+28800) rem 86400)) + 86400 - Now.

%% sort by ascii
sort(Str,[]) ->
  Str;
sort(Str,Acc) ->
  [[_,[StrAscii1],_]] = io_lib:format("~w",[string:substr(Str,1,1)]),
  [[_,[StrAscii2],_]] = io_lib:format("~w",[string:substr(Str,2,1)]),
  NStr =  string:substr(Str,3,length(Str)),
  {Acc1,NStr} = case list_to_integer(StrAscii1) >  list_to_integer(StrAscii2) of
    true ->
      {Acc ++ string:substr(Str,1,1),string:substr(Str,2,1) ++ string:substr(Str,3,length(Str))};
    _ ->
      {Acc ++ string:substr(Str,2,1),string:substr(Str,1,1) ++ string:substr(Str,3,length(Str))}
  end,
  sort(NStr,Acc1).


get_token(Username) ->
  {_, _, U} = os:timestamp(),
  list_to_binary(uuid:to_string(uuid:uuid1()) ++ binary_to_list(Username) ++ "-" ++ lists:flatten(io_lib:format("~6.10.0B", [U]))).