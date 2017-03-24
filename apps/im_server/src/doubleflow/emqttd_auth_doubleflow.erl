
-module( emqttd_auth_doubleflow ).

-export([
        check/3
        ]).

-define( USERNAME_HEAD, <<"username">> ).  %  用于双流机场进行验证的 token
-define( USERID_HEAD,   <<"uid">> ).        %  用于 im 自己验证的 uid

-define( TOKEN_HEAD,    <<"token">>  ).
-define( APPKEY_HEAD,   <<"password">> ).

% ----------------------------------------------------------------------------------------------------
% @doc Password 也是以 json 的格式传递进来的。
% eg <<{ \"username\":\"UserName\", \"token\":\"123456654321\" ,\"password\":\"xxxxxxxxx\"} >>
% 解析出来后 {<<"UserName">>, <<"123456654321">> , <<"xxxxxxxxx">> }
% ----------------------------------------------------------------------------------------------------
do_decode_passwd( Password ) ->
    ErlJson = jsx:decode( Password ),
    TokenDF = proplists:get_value( ?TOKEN_HEAD, ErlJson ),
    PassWordDF = proplists:get_value( ?APPKEY_HEAD , ErlJson ),
    UserNameDF = proplists:get_value( ?USERNAME_HEAD, ErlJson ),
    {UserNameDF, TokenDF, PassWordDF }.

do_check_token( UserNameDF, TokenDF  ) ->
    lager:info( " check token. UserName: ~p Token: ~p~n", [ UserNameDF, TokenDF ] ),
    true.

% ------------------------------------------------------------------
% @doc 判断用户名和密码是否正确
% ------------------------------------------------------------------
-spec check( UidDF::binary(), Password::binary(), PlatformType::any() ) -> true | false.
check( UidDF, Password, PlatformType ) when is_binary(UidDF) andalso is_binary( Password )  ->
    util:print(" login event con Uid:~p Password:~p Platfortype:~p ~n", [ UidDF, Password, PlatformType  ]),
    try
        {UserNameDF, TokenDF, PassWordDF} = do_decode_passwd( Password ),
        util:print("get UserNameDF:~p TokenDF:~p PassWordDF: ~p ~n",[ UserNameDF, TokenDF, PassWordDF ]),
        emqttd_auth_internal:check( UidDF, PassWordDF, PlatformType ) andalso do_check_token( UserNameDF, TokenDF )
    catch
        _M:_R ->
            lager:error("~p check error ~p~n ~p ~p ~n",[?MODULE, _M, _R, erlang:get_stacktrace()]),
            false
    end;
check( _UserName, _Password, _PlatformType ) ->
    lager:error("UserName:~p or Password:~p format error ~n",[_UserName, _Password]),
    false.


