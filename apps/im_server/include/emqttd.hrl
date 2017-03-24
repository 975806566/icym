%%------------------------------------------------------------------------------
%% Copyright (c) 2012-2015, Feng Lee <feng@emqtt.io>
%% 
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%% 
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.
%%------------------------------------------------------------------------------
%%% @doc
%%% emqtt header.
%%%
%%% @end
%%%-----------------------------------------------------------------------------

%------------------------------------------------------------------------------
%               @doc 所有的主题类型
%------------------------------------------------------------------------------

-define(COPYRIGHT,          "Copyright (C) 2012-2015, Feng Lee <feng@emqtt.io>").

-define(LICENSE_MESSAGE,    "Licensed under MIT"). 

-define(PROTOCOL_VERSION,   "MQTT/3.1.1").

-define(ERTS_MINIMUM,       "6.0").

-define(FILE_SERVER,        "FS").

-define(WEB_SERVER,         "WS").

-define(VIDEO_SERVER,       "VS").

-define(SEND_CHAT,          "chat").

-define(SEND_EXTRA,         "extra" ).

-define(SEND_FILE,          "sfile").               % 文件主题

-define(SEND_GROUP_FILE,    "sgfile").              % 群文件主题

-define(SEND_VIDEO,         "svideo").

-define(GET_FILE,           "file").

-define(GET_VIDEO,          "video").

-define(GET_WEB,            "http").

-define(GET_TOKEN,          "token").

-define(GET_STATUS,         "status").

-define(HTTP_TOPIC,         "http@all").

-define(FILE_TOPIC,         "file@all").

-define(VIDEO_TOPIC,        "video@all").

-define(GET_FILE_WS,        "file_ws").

-define(FILE_WS_TOPIC,      "file_ws@all").

-define(TOKEN_TOPIC,        "token@all").

-define(FILE_WS_SERVER,     "FW").

-define(SERVER_TIME_TOPIC,  "systime@all").

-define(GET_SERVER_TIME,    "systime").

-define(SEND_CHAT_EX,       "chat_ex").

-define(GET_OFF_LINE_MSG,   "offline_msg").

-define(STATE_SUB,          "state_sub").

-define(STATE_UNSUB,        "state_unsub").

-define(UN_BINDING,         "unbind").

-define(BINDING,            "bind").

-define(PUBLISH_FLAG,       "p").

-define(BUDDY_STATE_LIST,   "buddy_state_list").

-define(NOTICE_ADD_BUDDY,   "notice_add_buddy").

-define(NOTICE_REMOVE_BUDDY, "notice_remove_buddy").

-define(STATE_SUB_BUDDIES,  "state_sub_buddies").

-define(STATE_UNSUB_BUDDIES,"state_unsub_buddies").

-define(SYSKICK,            <<"sys@kick">>).

-define(OFLINE,             <<"online@">>).

-define(OFFLINE,            <<"offline@">>).

-define(ROOM_SIZE,          50).

-define(PARSE_DOMAIN,       "parse_domain").

-define(PARSE_DOMAIN_TOPIC, "parse_domain@all").


-define(A_SDK, 1).
-define(J_SDK, 2).
-define(L_SDK, 3).
-define(U_SDK, 4).
-define(W_SDK, 5).
-define(S_SDK, 6).
-define(I_SDK, 7).
-define(H_SDK, 8).


-define(MSG_TYPE_GROUP,     <<"g">> ).      % 消息类型群聊
-define(MSG_TYPE_PERSON,    <<"p">> ).      % 消息类型私聊，点对点消息


%%------------------------------------------------------------------------------
%% MQTT Retained Message
%%------------------------------------------------------------------------------
-record(mqtt_retained, {topic, qos, payload}).

-type mqtt_retained() :: #mqtt_retained{}.

%%------------------------------------------------------------------------------
%% MQTT User Management
%%------------------------------------------------------------------------------
-record(users, {
    user_id,
    username    :: binary(), 
    node_id,
    appkey_id,
    password  :: binary(),
    name
}).

-record(user_info, {
    id,
    appkey,
    ip,
    last_login_time,
    platform_type,
    ios_token,
    platform_special_flag = 0, %% 默认为0，不需要绑定平台专用0，需要绑定平台专用为1
    status = 0,                %% 状态（在线和离线）
    activation_time = 0,       %% 激活时间
    
    % -----------------------------------------------------------

    apply_time = #{ group_count => 0 },

    % 用于扩展其他字段，没有做出预留的字段出来，只能把 apply_time 用作其他的字段
    % 选用 maps 的好处在于，后期更换结构更加方便
    % #{ 
    %   group_count => 0,       % 当前已经订阅的群组数
    %   sub_status_list => []   % 订阅状态的列表
    % }
    % -----------------------------------------------------------

    login_count = 0,           %% 累计登录次数
    pay_flag = 0               %% 付费标示，0未付费，1付费
}).




-record(business, {
    appkey_id,
    appkey    :: binary(), 
    name      :: binary(),
    admin     :: binary(),
    password  :: binary(),
    secure    :: binary(),
    callback_url,
    createtime,
    activation = 0
    }).

-record(firend_list, {
    id,
    user_id,
    firend_id
    }).

-record(nodes, {
    id,
    node
    }).

-record(off_msg, {
    id,
    topic   :: binary(),
    message :: binary(),
    volume,
    qos,
    user_id,
    time
    }).

-record(user_off_msg_list, {
    id,
    offmsg_id,
    user_id
    }).

-record(group, {
    id,
    topic,
    name,
    createtime,
    create_id
    }).

-record(mqtt_client, {
    clientid    :: binary() | undefined,
    username    :: binary() | undefined,
    ipaddress   :: inet:ip_address(),
    client_pid  :: pid(),
    client_mon  :: reference(),
    clean_sess  :: boolean(),
    proto_ver   :: 3 | 4
}).

-record(url_map, {
    appkey,
    url
}).
