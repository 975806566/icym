
% ---------------------------------------------------------------------------------------
% @doc 用于 SDK 向双流机场的三种登录类型的转换
% 双流机场3种类型：
% 1：_pc
% 2: _wb
% 3: _ap
% ---------------------------------------------------------------------------------------
-module( double_convert ).

-include("emqttd.hrl").

-define( TAIL_PC,       "_pc" ).
-define( TAIL_WEB,      "_wb" ).
-define( TAIL_APP,      "_ap" ).

-export([
            get_real_uid/2,
            get_real_uid_list/1,
            get_uname_by_ruid/1
        ]).

% ------------------------------------------------------------------
% @doc 通过 Sdk 和 Username 获取 im 真正的 Uid
% ------------------------------------------------------------------
get_real_uid( Sdk, Username ) ->
    Tail = 
        case Sdk of
            ?W_SDK ->
                    ?TAIL_PC;
            ?J_SDK ->
                    ?TAIL_WEB;
            ?A_SDK ->
                    ?TAIL_APP;
            ?I_SDK ->
                    ?TAIL_APP;
            _OthersSdk ->
                    ?TAIL_APP
        end,
    list_to_binary( binary_to_list( Username ) ++ Tail ). 
            
get_real_uid_list( Username ) ->
    [ get_real_uid( ?W_SDK , Username ),
      get_real_uid( ?J_SDK , Username ),
      get_real_uid( ?I_SDK,  Username )].

get_uname_by_ruid( RUid0 ) ->
    RUid = binary_to_list( RUid0 ),
    list_to_binary( lists:sublist( RUid, length(RUid) - 3) ).
