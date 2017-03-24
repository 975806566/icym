%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd message.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_message).

-include("emqttd.hrl").

-include("emqttd_packet.hrl").

-export([from_packet/1, to_packet/1]).

-export([set_flag/1, set_flag/2, unset_flag/1, unset_flag/2]).

-export([dump/1]).

%%------------------------------------------------------------------------------
%% @doc
%% Message from Packet.
%%
%% @end
%%------------------------------------------------------------------------------
-spec from_packet(mqtt_packet()) -> mqtt_message().
from_packet(#mqtt_packet{header   = #mqtt_packet_header{type   = ?PUBLISH,
                                                        retain = Retain,
                                                        qos    = Qos,
                                                        dup    = Dup}, 
                         variable = #mqtt_packet_publish{topic_name = Topic,
                                                         packet_id  = PacketId},
                         payload  = Payload}) ->
	#mqtt_message{msgid    = PacketId,
                  qos      = Qos,
                  retain   = Retain,
                  dup      = Dup,
                  topic    = Topic,
                  payload  = Payload};

from_packet(#mqtt_packet_connect{will_flag  = false}) ->
    undefined;

from_packet(#mqtt_packet_connect{will_retain = Retain,
                                 will_qos    = Qos,
                                 will_topic  = Topic,
                                 will_msg    = Msg}) ->
    #mqtt_message{retain  = Retain,
                  qos     = Qos,
                  topic   = Topic,
                  dup     = false,
                  payload = Msg}.

%%------------------------------------------------------------------------------
%% @doc
%% Message to packet
%%
%% @end
%%------------------------------------------------------------------------------
-spec( to_packet( mqtt_message() ) -> mqtt_packet() ).

to_packet(#mqtt_message{msgid   = MsgId,
                        qos     = Qos,
                        retain  = Retain,
                        dup     = Dup,
                        topic   = Topic,
                        payload = Payload}) ->

    PacketId = if 
        Qos =:= ?QOS_0 -> undefined; 
        true -> MsgId 
    end,  

    #mqtt_packet{header = #mqtt_packet_header{type 	 = ?PUBLISH,
                                              qos    = Qos,
                                              retain = Retain,
                                              dup    = Dup},
                 variable = #mqtt_packet_publish{topic_name = Topic,
                                                 packet_id  = PacketId},
                 payload = Payload}.

%%------------------------------------------------------------------------------
%% @doc
%% set dup, retain flag
%%
%% @end
%%------------------------------------------------------------------------------
-spec set_flag(mqtt_message()) -> mqtt_message().
set_flag(Msg) ->
    Msg#mqtt_message{dup = true, retain = true}.

-spec set_flag(atom(), mqtt_message()) -> mqtt_message().
set_flag(dup, Msg = #mqtt_message{dup = false}) -> 
    Msg#mqtt_message{dup = true};
set_flag(retain, Msg = #mqtt_message{retain = false}) ->
    Msg#mqtt_message{retain = true};
set_flag(Flag, Msg) when Flag =:= dup orelse Flag =:= retain -> Msg.


%%------------------------------------------------------------------------------
%% @doc
%% Unset dup, retain flag
%%
%% @end
%%------------------------------------------------------------------------------
-spec unset_flag(mqtt_message()) -> mqtt_message().
unset_flag(Msg) ->
    Msg#mqtt_message{dup = false, retain = false}.

-spec unset_flag(dup | retain | atom(), mqtt_message()) -> mqtt_message().
unset_flag(dup, Msg = #mqtt_message{dup = true}) -> 
    Msg#mqtt_message{dup = false};
unset_flag(retain, Msg = #mqtt_message{retain = true}) ->
    Msg#mqtt_message{retain = false};
unset_flag(Flag, Msg) when Flag =:= dup orelse Flag =:= retain -> Msg.

%%------------------------------------------------------------------------------
%% @doc
%% Dump mqtt message.
%%
%% @end
%%------------------------------------------------------------------------------
dump(#mqtt_message{msgid= MsgId, qos = Qos, retain = Retain, dup = Dup, topic = Topic}) ->
    io_lib:format("Message(MsgId=~p, Qos=~p, Retain=~s, Dup=~s, Topic=~s)",
              [MsgId, Qos, Retain, Dup, Topic]).

