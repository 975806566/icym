%%-----------------------------------------------------------------------------
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

%%------------------------------------------------------------------------------
%% Core PubSub Topic
%%------------------------------------------------------------------------------
-record(topic, {
    topic           :: binary(),
    node_id
}).

-type topic() :: #topic{}.

-record(topic_subscriber, {
    id,
    topic :: binary(),
    qos = 0  :: non_neg_integer(),
    user_id   :: binary()}).

-record(topic_trie_node, {
    node_id        	:: binary() | atom(),
    edge_count = 0  :: non_neg_integer(),
    topic    		:: binary()
}).

-record(topic_trie_edge, {
    node_id :: binary() | atom(),
    word    :: binary() | atom()
}).

-record(topic_trie, {
    edge    :: #topic_trie_edge{},
    node_id :: binary() | atom()
}).

-record(ts_id,    {type, counter}).
-record(tsu_id,    {type, counter}).

-define(SUB_ACK_FAIL,       16#80).
