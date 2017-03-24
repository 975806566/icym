-module(emqttd_topic).

-import(lists, [reverse/1]).

%% ------------------------------------------------------------------------
%% Topic semantics and usage
%% ------------------------------------------------------------------------
%% A topic must be at least one character long.
%%
%% Topic names are case sensitive. For example, ACCOUNTS and Accounts are two different topics.
%%
%% Topic names can include the space character. For example, Accounts payable is a valid topic.
%%
%% A leading "/" creates a distinct topic. For example, /finance is different from finance. /finance matches "+/+" and "/+", but not "+".
%%
%% Do not include the null character (Unicode \x0000) in any topic.
%%
%% The following principles apply to the construction and content of a topic tree:
%%
%% The length is limited to 64k but within that there are no limits to the number of levels in a topic tree.
%%
%% There can be any number of root nodes; that is, there can be any number of topic trees.
%% ------------------------------------------------------------------------

-include("emqttd_topic.hrl").
 
-export([new/1, type/1, match/2, validate/1, triples/1, words/1]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec new( binary() ) -> topic().

-spec type(topic() | binary()) -> direct | wildcard.

-spec match(binary(), binary()) -> boolean().

-spec validate({name | filter, binary()}) -> boolean().

-endif.

%%----------------------------------------------------------------------------

-define(MAX_TOPIC_LEN, 65535).

%% ------------------------------------------------------------------------
%% New Topic
%% ------------------------------------------------------------------------
new(Name) when is_binary(Name) ->
	#topic{topic = Name}.

%% ------------------------------------------------------------------------
%% Topic Type: direct or wildcard
%% ------------------------------------------------------------------------
type(#topic{ topic = Name }) when is_binary(Name) ->
	type(Name);
type(Topic) when is_binary(Topic) ->
	type2(words(Topic)).

type2([]) -> 
    direct;
type2(['#'|_]) ->
    wildcard;
type2(['+'|_]) ->
    wildcard;
type2([_H |T]) ->
    type2(T).

%% ------------------------------------------------------------------------
%% Match Topic. B1 is Topic Name, B2 is Topic Filter.
%% ------------------------------------------------------------------------
match(Name, Filter) when is_binary(Name) and is_binary(Filter) ->
	match(words(Name), words(Filter));
match([], []) ->
	true;
match([H|T1], [H|T2]) ->
	match(T1, T2);
match([<<$$, _/binary>>|_], ['+'|_]) ->
    false;
match([_H|T1], ['+'|T2]) ->
	match(T1, T2);
match([<<$$, _/binary>>|_], ['#']) ->
    false;
match(_, ['#']) ->
	true;
match([_H1|_], [_H2|_]) ->
	false;
match([_H1|_], []) ->
	false;
match([], [_H|_T2]) ->
	false.

%% ------------------------------------------------------------------------
%% Validate Topic 
%% ------------------------------------------------------------------------
validate({_, <<>>}) ->
	false;
validate({_, Topic}) when is_binary(Topic) and (size(Topic) > ?MAX_TOPIC_LEN) ->
	false;
validate({filter, Topic}) when is_binary(Topic) ->
	validate2(words(Topic));
validate({name, Topic}) when is_binary(Topic) ->
	Words = words(Topic),
	validate2(Words) and (not include_wildcard(Words)).

validate2([]) ->
    true;
validate2(['#']) -> % end with '#'
    true;
validate2(['#'|Words]) when length(Words) > 0 -> 
    false; 
validate2([''|Words]) ->
    validate2(Words);
validate2(['+'|Words]) ->
    validate2(Words);
validate2([W|Words]) ->
    case validate3(W) of
        true -> validate2(Words);
        false -> false
    end.

validate3(<<>>) ->
    true;
validate3(<<C/utf8, _Rest/binary>>) when C == $#; C == $+; C == 0 ->
    false;
validate3(<<_/utf8, Rest/binary>>) ->
    validate3(Rest).

include_wildcard([])        -> false;
include_wildcard(['#'|_T])  -> true;
include_wildcard(['+'|_T])  -> true;
include_wildcard([ _ | T])  -> include_wildcard(T).

%% ------------------------------------------------------------------------
%% Topic to Triples
%% ------------------------------------------------------------------------
triples(Topic) when is_binary(Topic) ->
	triples(words(Topic), root, []).

triples([], _Parent, Acc) ->
    reverse(Acc);

triples([W|Words], Parent, Acc) ->
    Node = join(Parent, W),
    triples(Words, Node, [{Parent, W, Node}|Acc]).

join(root, W) ->
    bin(W);
join(Parent, W) ->
    <<(bin(Parent))/binary, $/, (bin(W))/binary>>.

bin('')  -> <<>>;
bin('+') -> <<"+">>;
bin('#') -> <<"#">>;
bin( B ) when is_binary(B) -> B.

%% ------------------------------------------------------------------------
%% Split Topic to Words
%% ------------------------------------------------------------------------
words(Topic) when is_binary(Topic) ->
    [word(W) || W <- binary:split(Topic, <<"/">>, [global])].

word(<<>>)    -> '';
word(<<"+">>) -> '+';
word(<<"#">>) -> '#';
word(Bin)     -> Bin.


