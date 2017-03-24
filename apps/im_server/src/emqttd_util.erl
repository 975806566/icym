

-module( emqttd_util ).


-export([
        get_env/3
        ]).

% ---------------------------------------------------------------
% @doc 获取系统配置
% ---------------------------------------------------------------
-spec get_env( App::atom(), Key::atom(), Default::atom() ) -> {ok , Res::any()}.
get_env(App, Key, Default) ->
    case application:get_env(App, Key) of
    {ok, Value} ->
            {ok, Value};
        _ ->
            {ok, Default}
    end.

