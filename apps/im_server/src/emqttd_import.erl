%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd import test data.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_import).

-include("emqttd.hrl").
-include("emqttd_topic.hrl").
-include("mysql.hrl").

-export([create_appkey/2, import/3, import2/3]).

import(Length, Username, <<"4cdad356-85b4-008627">>) ->
    Appkey = <<"4cdad356-85b4-008627">>,
    lists:foreach(
        fun(Index) -> 
            Id = integer_to_binary(mnesia_tools:get_next_user_id()),
            IndexBin = integer_to_binary(Index),
            Username2 = <<Username/binary,IndexBin/binary>>,
            mnesia_tools:dirty_write(users, #users{user_id = Id, username  = Username2, appkey_id = 61}),
            mnesia_tools:dirty_write(user_info, #user_info{id =Id, appkey = Appkey})
            % sub(IndexBin, Appkey)
        end, lists:seq(1, Length)).

import2(Length, Username, Appkey) ->
    [[Business_id]] = mysql_utils:select(?IM_POOL,business,"business_id",[{appkey,"=",Appkey}],[]),
    lists:foreach(
        fun(Index) -> 
            BaseIndex = <<"888888">>,
            Nun = integer_to_binary(Index),
            Id  = <<BaseIndex/binary,Nun/binary>>,
            Username2 = <<Username/binary,BaseIndex/binary>>,
            mnesia_tools:dirty_write(users, #users{user_id = Id, username  = Username2, appkey_id = Business_id}),
            mnesia_tools:dirty_write(user_info, #user_info{id =Id, appkey = Appkey})
            % sub(Id, Appkey)
        end, lists:seq(1, Length)).

create_appkey(Appkey, Secure) ->
    Record = #mysql_business{
            appkey        = Appkey,
            business_name = <<"testa">>,
            admin         = <<"admin">>,
            password      = <<"123456">>,
            secretkey     = Secure,
            createtime    = 'now()'
        },
    mysql_utils:insert(?IM_POOL, business, Record, ?record_field(mysql_business)).

% sub(Username, Appkey) ->
%     mnesia_tools:dirty_write(topic_subscriber, 
%         #topic_subscriber{
%             id = {Appkey, Username},
%             topic = Appkey,
%             qos = 1,
%             user_id = Username}),
%     mnesia_tools:dirty_write(topic, emqttd_topic:new(Appkey)),
%     case mnesia_tools:dirty_read(topic_trie_node, Appkey) of
%         [TrieNode=#topic_trie_node{topic=undefined}] ->
%             mnesia_tools:dirty_write(topic_trie_node, TrieNode#topic_trie_node{topic=Appkey});
%         [#topic_trie_node{topic=Appkey}] ->
%             ok;
%         [] ->
%             [emqttd_pubsub:trie_add_path(Triple) || Triple <- emqttd_topic:triples(Appkey)],
%             mnesia_tools:dirty_write(topic_trie_node, #topic_trie_node{node_id=Appkey, topic=Appkey})
%     end, 
%     io:format("----Username:~p~n", [Username]).
