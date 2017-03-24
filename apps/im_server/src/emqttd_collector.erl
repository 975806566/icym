%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd collector.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_collector).

-behaviour(gen_server).
-export([start/1, start_link/1, get_data/0]).
-export([stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {last, tref, ip, port, ws_port}).

-define(TIMER, 5000).
start(ServerOpts) ->
  gen_server:start({local, ?MODULE}, ?MODULE, [ServerOpts], []).


start_link(ServerOpts) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [ServerOpts], []).

stop() ->
  gen_server:call(?MODULE, stop).

%% gen_server callbacks

%% @spec init([]) -> {ok, State}
%% @doc gen_server init, opens the server in an initial state.
init([ServerOpts]) ->
    Ip = proplists:get_value(ip, ServerOpts),
    Port = proplists:get_value(port, ServerOpts),
    WSPort = proplists:get_value(ws_port, ServerOpts),
    erlang:send_after(?TIMER, self(), collector_message),
    {ok, #state{last = stamp(), ip = list_to_binary(Ip), port = Port, ws_port = WSPort}}.

%% @spec handle_call(Args, From, State) -> tuple()
%% @doc gen_server callback.
handle_call(stop, _From, State) ->
  {stop, shutdown, stopped, State};
handle_call(_Req, _From, State) ->
  {reply, {error, badrequest}, State}.

%% @spec handle_cast(Cast, State) -> tuple()
%% @doc gen_server callback.
handle_cast(_Req, State) ->
  {noreply, State}.

%% @spec handle_info(Info, State) -> tuple()
%% @doc gen_server callback.
handle_info(collector_message, State = #state{ip = Ip, port = Port, ws_port = WSPort}) ->
  Now = stamp(),
  Weight = get_data(),
  case et_eredis:get("IM") of
    [] ->
      et_eredis:set("IM",[{<<"ip">>, Ip}, {<<"port">>, Port}, {<<"weight">>, Weight}]),
      et_eredis:set("IW",[{<<"ip">>, Ip}, {<<"port">>, WSPort}, {<<"weight">>, Weight}]);
    Value ->
      RedisIp =  proplists:get_value(<<"ip">>,Value),
      case RedisIp =:= Ip of
        true ->
          et_eredis:set("IM",[{<<"ip">>,Ip}, {<<"port">>, Port}, {<<"weight">>, Weight}]),
          et_eredis:set("IW",[{<<"ip">>, Ip}, {<<"port">>, WSPort}, {<<"weight">>, Weight}]);
        false ->
          Node = lists:concat(["im_server", "@", binary_to_list(RedisIp)]),
          case emqttd:is_running(list_to_atom(Node)) of
              true ->
                  RedisWeight =  proplists:get_value(<<"weight">>,Value,100),
                  case Weight < RedisWeight of
                    true ->
                      et_eredis:set("IM",[{<<"ip">>,Ip}, {<<"port">>, Port}, {<<"weight">>, Weight}]),
                      et_eredis:set("IW",[{<<"ip">>, Ip}, {<<"port">>, WSPort}, {<<"weight">>, Weight}]);
                    false ->
                      ok
                  end;
              false ->
                et_eredis:set("IM",[{<<"ip">>,Ip}, {<<"port">>, Port}, {<<"weight">>, Weight}]),
                et_eredis:set("IW",[{<<"ip">>, Ip}, {<<"port">>, WSPort}, {<<"weight">>, Weight}])
          end
      end
  end,
  erlang:send_after(?TIMER, self(), collector_message),
  {noreply, State#state{last = Now}};
handle_info(_Info, State) ->
  {noreply, State}.

%% @spec terminate(Reason, State) -> ok
%% @doc gen_server termination callback.
terminate(_Reason, _State) ->
  % {ok, cancel} = timer:cancel(State#state.tref),
  ok.

%% @spec code_change(_OldVsn, State, _Extra) -> State
%% @doc gen_server code_change callback (trivial).
code_change(_Vsn, State, _Extra) ->
  {ok, State}.


stamp() ->
  erlang:localtime().

get_data() ->
    Memoryinfo = memsup:get_system_memory_data(),
    Free_memory = proplists:get_value(free_memory,Memoryinfo),
    Total_memory = proplists:get_value(total_memory,Memoryinfo),
    MemoryUsed = (Total_memory - Free_memory)/Total_memory,
    Cpuinfo = cpu_sup:util([per_cpu]),
    {Total_cpu,Cpu_used} = lists:foldl(fun({_,Tmp_Cpu_used,Tmp_Cpu_free,_},{Acc1,Acc2}) ->
        Tmp_total_cpu = Tmp_Cpu_used + Tmp_Cpu_free,
        {Acc1 + Tmp_total_cpu,Acc2 + Tmp_Cpu_used}
        end,{0,0},Cpuinfo),
    CpuUsed_Precent = Cpu_used/Total_cpu,
    CpuUsed_Precent * 50 + MemoryUsed * 50.

