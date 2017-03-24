%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd core pubsub.
%%%
%%% TODO: should not use gen_server:call to create, subscribe topics...
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_pubsub).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

-include("emqttd.hrl").

-include("emqttd_topic.hrl").

-include("emqttd_packet.hrl").

-include_lib("stdlib/include/qlc.hrl").

%% API Exports 

-export([start_link/0]).

-export([subscribe/2,
        unsubscribe/2,
        publish/2,
        publish/3,
        dispatch/3]).

%% gen_server Function Exports

-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3,
        route_to_groups/4]).

-define(PUBLISH_FLAG1,      "p@").
-define(MAX_TOPIC_COUNT,    1000).

-record(state, {max_subs = 0}).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% Start Pubsub.
%%
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%------------------------------------------------------------------------------
%% @doc
%% Subscribe Topic or Topics
%%
%% @end
%%------------------------------------------------------------------------------
-spec subscribe({binary(), mqtt_qos()} | list(), binary()) -> {ok, list(mqtt_qos())}.
subscribe({Topic, Qos}, Username) when is_binary(Topic) ->
    subscribe([{Topic, Qos}], Username);

subscribe(Topics = [{_Topic, _Qos}|_], Username) ->
    subscribe(Topics, Username, []).

subscribe([], _UserId, Acc) ->
    {ok, lists:reverse(Acc)};
%%TODO: check this function later.
subscribe([{TopicId, Qos}|Topics], UserId, Acc) ->
    util:print("[sub_topic] => [UserId:~p,TopicId:~p,Qos:~p]~n", [UserId, TopicId, Qos]),
    SubQos = do_check_topic_sum( UserId, TopicId, Qos ),
    subscribe(Topics, UserId, [SubQos|Acc]).


do_get_topic_len( TopicList ) ->
    Fun = fun( Topic, AccCount) ->
        case Topic of
            <<"p@",_Resb/binary>> ->
                AccCount + 1;
            _NotSame ->
                AccCount
        end
    end,
    lists:foldl( Fun, 0, TopicList).

% ------------------------------------------------------------------------------
% 判断用户订阅的主题数是否已经达到上限
% 1: 如果已经达到上限： 那么返回 ?USB_ACK_FAIL
% 2: 如果没有达到上限： 返回成功订阅的 QOS
% ------------------------------------------------------------------------------
-spec do_check_topic_sum( UserId::binary(), TopicId::binary(), Qos::integer() ) -> true | false.
do_check_topic_sum( UserId, TopicId, Qos ) ->
    case mnesia:dirty_read( user_info, UserId ) of
        [] ->
            ?SUB_ACK_FAIL;
        [ UserInfo ] ->
            ExtraMap = UserInfo#user_info.apply_time,
            CurTopicCount = 
            case is_map( ExtraMap ) of
                true ->
                    maps:get( group_count, ExtraMap, 0 );
                _NotMap ->
                    Len = do_get_topic_len( mnesia_tools:dirty_index_read(topic_subscriber, UserId, #topic_subscriber.user_id) ),
                    mnesia:dirty_write( user_info, UserInfo#user_info{apply_time = #{group_count => Len }} ),
                    Len
            end,

            MaxTopicCount = util:get_value_cache( emqttd, max_topic_count, ?MAX_TOPIC_COUNT ),

            case CurTopicCount >= MaxTopicCount of
                true ->
                    ?SUB_ACK_FAIL;
                _NotBigger ->

                    NewTopicCount =
                    case mnesia:dirty_read( topic_subscriber, {TopicId, UserId} ) of
                        [] ->
                            CurTopicCount + 1;
                        [_TR] ->
                            CurTopicCount
                    end,

                    mnesia:dirty_write( user_info, UserInfo#user_info{apply_time = #{group_count => NewTopicCount }}),
                    Subscriber = #topic_subscriber{id = {TopicId, UserId}, topic = TopicId, qos = Qos, user_id=UserId},
                    mnesia:dirty_write( emqttd_topic:new(TopicId) ),
                    mnesia:dirty_write(Subscriber),
                    Qos
            end
    end.
   

%%------------------------------------------------------------------------------
%% @doc
%% Unsubscribe Topic or Topics
%%
%% @end
%%------------------------------------------------------------------------------
%%TODO: check this function later.
unsubscribe(Topics, UserId) ->
    Subscribers = mnesia_tools:index_read(topic_subscriber, UserId, #topic_subscriber.user_id),
    lists:foreach(
        fun(Sub = #topic_subscriber{topic = Topic}) ->
            util:print("[un_sub_topic] => [UserId:~p,Topic:~p]~n", [ UserId, Topic ]),
            case mnesia:dirty_read( user_info, UserId ) of
                [] ->
                    ok;
                [ UserInfo ] ->
                    case lists:member(Topic, Topics) of
                        true -> 
                            mnesia_tools:delete_object(Sub),
                            OldMap = UserInfo#user_info.apply_time,
                            case is_map( OldMap  ) of
                                true ->
                                    CurTopicCount = maps:get( group_count, OldMap , 1),
                                    mnesia:dirty_write( user_info, UserInfo#user_info{ apply_time = OldMap#{ group_count => CurTopicCount - 1}} );
                                _NotChange ->
                                    ok
                            end;
                        false -> ok
                    end
            end
        end, Subscribers).

%%------------------------------------------------------------------------------
%% Publish to cluster node.
%%------------------------------------------------------------------------------
publish( Msg=#mqtt_message{topic = Gid}, FromUserName ) ->
    publish( Gid, Msg, FromUserName ).

publish(Gid, Msg, FromUsername ) when is_binary(Gid) ->
    case mnesia_tools:dirty_read(topic, Gid) of
        [] -> ok;
        [#topic{topic = Gid}] ->
            send_message(Gid, Msg, FromUsername )
    end.

% ---------------------------------------------------------------------------------------------
% @doc 群发消息
% ---------------------------------------------------------------------------------------------
send_message(Gid, Msg, FromUsername ) when is_binary( Gid ) ->

    % -------------------------------------------------------------
    %  如果传进来的 Gid 为 p@123 那么返回的主题也应该是 p@123
    %  如果传进来的 Gid 为群Gid，那么返回的主题为 Gid@FromUserName
    % -------------------------------------------------------------
    Topic = case string:left(binary_to_list(Gid), 2) of
        ?PUBLISH_FLAG1 ->
            Gid;
        _ ->
            <<Gid/binary, <<"@">>/binary, FromUsername/binary>>
    end,
    route_to_groups( Topic, Gid, Msg, FromUsername ).

do_get_min_qos(Msg, SendQos, SubQos) ->
        case SendQos > SubQos of
            true ->
                Msg#mqtt_message{ qos = SubQos };
            _False -> 
                Msg
        end.

route_to_groups( Topic, Gid, Msg = #mqtt_message{qos = SendQos, payload = Content}, FromUsername ) ->

    emqttd_client_tools:msg_info( FromUsername, Gid, Content, group ),

    Subscribers = mnesia_tools:dirty_index_read(topic_subscriber, Gid, #topic_subscriber.topic),
    NewMsgId = off_msg_id_svc:get_msg_id(),
    off_msg_api: new_tmp_group_msg( NewMsgId, FromUsername, Topic, Content, SendQos, util:longunixtime() ),
    Msg0 = Msg#mqtt_message{ topic = Topic },    

    Fun = fun(#topic_subscriber{qos = SubQos, user_id = ToUid}) ->
        try
            case ToUid =:= FromUsername of
                true ->
                    ok;
                false ->
                    Msg1 = do_get_min_qos( Msg0, SendQos, SubQos ),
                    case emqttd_cm:lookup( ToUid ) of
                        undefined ->
                            [UserInfo] = mnesia:dirty_read(user_info, ToUid),
                            case UserInfo#user_info.platform_type =:= ?H_SDK of
                                true ->
                                    emqttd_ham:send_group_ham(
                                                                UserInfo#user_info.appkey, 
                                                                FromUsername, 
                                                                ToUid, 
                                                                Gid, 
                                                                Msg1#mqtt_message.payload, 
                                                                Msg1#mqtt_message.qos);
                                false ->
                                    [ User ] = mnesia:dirty_read(users, ToUid),
                                    case emqttd_route:check_user_online( User ) of
                                        false ->
                                            do_save_offline_msg_group( NewMsgId, ToUid, Msg1#mqtt_message.qos, UserInfo, Content);
                                        Node ->
                                            cast_svc:cast(Node#nodes.node, ?MODULE, dispatch, [ToUid, Msg1, NewMsgId])
                                    end
                            end;
                        Pid -> 
                            gen_server:cast(Pid, {send_pub_msg, Msg1, Msg1#mqtt_message.qos, ToUid})
                    end
            end
        catch
            _M:_R ->
                skip
        end
    end,
    [Fun(Subscriber) ||  Subscriber <-Subscribers],
    length(Subscribers).

do_save_offline_msg_group(_MsgId, _Uid, ?QOS_0, _UserInfo, _Content ) ->
    skip;
do_save_offline_msg_group(MsgId, Uid, Qos, UserInfo, Content ) ->
    NowTime = util:longunixtime(),
    case (UserInfo#user_info.platform_type =:= ?I_SDK) andalso(UserInfo#user_info.ios_token =/= undefined) of
        true ->
            [User] = mnesia:dirty_read( users, Uid ),
            NickName =
            case User#users.name of
                undefined ->
                    User#users.username;
                _NotUndefined ->
                    User#users.name
            end,
            off_msg_api: new_index_msg(
                                        Uid, 
                                        MsgId, 
                                        Qos, 
                                        <<"g">>, 
                                        {
                                            NickName, 
                                            UserInfo#user_info.appkey, 
                                            UserInfo#user_info.ios_token, 
                                            Content 
                                        }, NowTime  );
        _NotIos ->
            off_msg_api: new_index_msg(Uid, MsgId, Qos, <<"g">>, not_ios, NowTime )
    end.
   
%%------------------------------------------------------------------------------
%% @doc
%% Dispatch Locally. Should only be called by publish.
%%
%% @end
%%------------------------------------------------------------------------------
dispatch(UserId, Msg1, NewMsgId) ->
    case emqttd_cm:lookup(UserId) of
        undefined ->
            [UserInfo] = mnesia:dirty_read(user_info, UserId),
            do_save_offline_msg_group( NewMsgId, UserId, Msg1#mqtt_message.qos, UserInfo, Msg1#mqtt_message.payload);
        Pid -> 
            gen_server:cast(Pid, {send_pub_msg, Msg1, Msg1#mqtt_message.qos, UserId})
    end.


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([]) ->
    {ok, #state{}}.


handle_call(Req, _From, State) ->
    lager:error("Bad Req: ~p", [Req]),
    {reply, error, State}.

handle_cast(Msg, State) ->
    lager:error("Bad Msg: ~p", [Msg]),
    {noreply, State}.

%% a new record has been written.
handle_info({mnesia_table_event, {write, #topic_subscriber{user_id = Pid}, _ActivityId}}, State) ->
    erlang:monitor(process, Pid),
    {noreply, State};

handle_info({mnesia_table_event, _Event}, State) ->
    {noreply, State};

handle_info({'DOWN', _Mon, _Type, DownPid, _Info}, State) ->
    F = fun() -> 
            [mnesia_tools:delete_object(Sub) || Sub <- mnesia_tools:index_read(topic_subscriber, DownPid, #topic_subscriber.user_id)]
        end,
    case catch mnesia:transaction(F) of
        {atomic, _} -> ok;
        {aborted, Reason} -> lager:error("Failed to delete 'DOWN' subscriber ~p: ~p", [DownPid, Reason])
    end,        
    {noreply, State};

handle_info(Info, State) ->
    lager:error("Bad Info: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================
