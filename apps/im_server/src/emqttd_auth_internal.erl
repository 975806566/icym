%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd internal authentication.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_auth_internal).

-include("emqttd.hrl").

-export([init/1, check/3]).

init(_Opts) ->
    ok.

check(undefined, _, _) -> false;

check(_, undefined, _) -> false;

check(Username, Password, PlatformType)->
    RUid = util:get_real_uid( PlatformType, Username ),
    case mnesia:dirty_read(users, RUid ) of
    [#users{}] ->
        case mnesia:dirty_read(user_info, RUid ) of
            [] -> false;
            [UserInfo = #user_info{appkey = Appkey}] ->
                RPasswd = md5_string:md5_hex(<<Appkey/binary, Username/binary>>),
                case binary_to_list(Password) =:=  RPasswd of
                    true ->
                        case UserInfo#user_info.platform_special_flag =:= 0 of
                            true -> 
                                true;
                            false ->
                                case lists:member(UserInfo#user_info.platform_type, [ ?L_SDK, ?U_SDK, ?H_SDK]) of
                                    true ->
                                        UserInfo#user_info.platform_type =:= PlatformType;
                                    false->
                                        lists:member(PlatformType , [?S_SDK, ?A_SDK, ?I_SDK, ?W_SDK, ?J_SDK])
                                end
                        end;
                    false ->
                        lager:error("auth check error. md5 not match ~p ~p ~n",[ Password, RPasswd ]),
                        false
                end
        end;
    _ -> 
        lager:error("auth check error. users table no this Uid ~p ~n", [ RUid ]),
        false
    end.
