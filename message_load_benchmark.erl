-module(message_load_benchmark).

-export([start/0]).

-define(NumProcesses, 96).
-define(WarmPeriod, timer:seconds(5*60)).
-define(CollectPeriod, timer:seconds(60)).
-define(TimeUnit, microsecond).
-define(WorkerReceiveWait, 10).

start() ->
    io:format("Starting ~p processes~n", [?NumProcesses]),
    Pids = do_start(?NumProcesses, []),
    Map = maps:from_list(Pids),
    persistent_term:put(?MODULE, Map),

    M = [ erlang:monitor(process, Pid) || {_, Pid} <- Pids ],

    io:format("Warming up (waiting ~p ms)~n", [?WarmPeriod]),
    [ erlang:send(Pid, start) || {_, Pid} <- Pids ],
    timer:sleep(?WarmPeriod),

    io:format("Gathering stats (waiting ~p ms)~n", [?CollectPeriod]),
    [ erlang:send(Pid, collect) || {_, Pid} <- Pids ],
    timer:sleep(?CollectPeriod),

    io:format("Stopping test~n~n", []),
    Self = self(),
    DataRefs = [ begin
          Ref = make_ref(),
          erlang:send(Pid, {stop, Self, Ref}),
          Ref
      end || {_, Pid} <- Pids ],
    Data = receive_data(DataRefs, []),
    receive_downs(M),
    print_report(Data).

print_report(Data) ->
    {USum, NS, NF} = lists:foldl(fun({Si, Ti, Fi}, {S, T, F}) -> {S+Si, T+Ti, F+Fi} end, {0, 0, 0}, Data),

    io:format("== System ==~n"),
    io:format("~n"),
    Uname = string:trim(os:cmd("uname -a")),
    io:format("~s~n", [Uname]),
    io:format("~s~n", [string:trim(erlang:system_info(system_version))]),
    print_system(Uname),
    io:format("~n"),
    io:format("== Parameters ==~n"),
    io:format("~n"),
    io:format("Processes = ~p~n", [?NumProcesses]),
    io:format("Worker recv wait = ~p ms~n", [?WorkerReceiveWait]),
    io:format("~n"),
    io:format("== Results ==~n"),
    io:format("~n"),
    io:format("NGood = ~p~n", [NS]),
    io:format("Goodput = ~p msg/sec~n", [1000*(NS / ?CollectPeriod)]),
    io:format("Latency = ~p us (avg)~n", [USum / NS]),
    io:format("~n"),
    io:format("NFlush = ~p~n", [NF]),
    io:format("Flushput = ~p msg/sec~n", [1000*(NF / ?CollectPeriod)]).

print_system("Darwin" ++ _) ->
    io:format("machdep.cpu.brand_string: ~s~n", [string:trim(os:cmd("sysctl -n machdep.cpu.brand_string"))]);
print_system(_) ->
    io:format("ec2_metadata.instance-type: ~s~n", [string:trim(os:cmd("facter ec2_metadata.instance-type"))]).

do_start(0, Acc) ->
    Acc;
do_start(N, Acc) ->
    Pid = spawn_link(fun() -> worker_loop(idle, nocollect, {0,0,0}) end),
    do_start(N-1, [{N, Pid}|Acc]).

worker_loop(idle, Collect, Data) ->
    receive
        start ->
            worker_loop(start, Collect, Data);
        stop ->
            ok;
        collect ->
            worker_loop(idle, collect, Data);
        {Ref, T1} when is_reference(Ref) ->
            T2 = erlang:monotonic_time(?TimeUnit),
            Data2 = receive_message(Ref, T1, T2, Collect, Data),
            worker_loop(idle, Collect, Data2)
    end;
worker_loop(start, Collect, Data) ->
    case select_target() of
        Target when is_pid(Target) ->
            erlang:send_nosuspend(Target, {make_ref(), erlang:monotonic_time(?TimeUnit)});
        _ ->
            ok
    end,
    Data2 = worker_flush(Collect, Data),
    receive
        {stop, Recv, Ref} ->
            erlang:send(Recv, {Ref, Data});
        collect ->
            worker_loop(start, collect, Data2);
        {Ref, T1} when is_reference(Ref) ->
            T2 = erlang:monotonic_time(?TimeUnit),
            Data3 = receive_message(Ref, T1, T2, Collect, Data2),
            worker_loop(start, Collect, Data3)
    after ?WorkerReceiveWait ->
        worker_loop(start, Collect, Data2)
    end.

select_target() ->
    Map = #{} = persistent_term:get(?MODULE),
    Size = map_size(Map),
    true = Size > 1,
    Idx = rand:uniform(Size),
    Self = self(),
    case maps:get(Idx, Map) of
        Self ->
            undefined;
        Pid ->
            Pid
    end.

receive_message(_Ref, T1, T2, Collect, Data) ->
    case process_info(self(), message_queue_len) of
        {message_queue_len, 0} ->
            Diff = T2 - T1,
            collect_diff(Diff, Collect, Data);
        _ ->
            worker_flush(Collect, Data)
    end.

worker_flush(Collect, Data) ->
    Flushed = do_worker_flush(0),
    collect_flush(Flushed, Collect, Data).

do_worker_flush(N) ->
    receive
        {Ref, _} when is_reference(Ref) ->
            do_worker_flush(N+1)
    after 0 ->
              N
    end.

receive_data([], Acc) ->
    Acc;
receive_data([Ref|Refs], Acc) ->
    receive
        {Ref, DataItem} ->
            receive_data(Refs, [DataItem|Acc])
    end.

receive_downs([]) ->
    ok;
receive_downs([M|Rest]) ->
    receive
        {'DOWN', M, process, _Pid, _Reason} ->
            receive_downs(Rest)
    end.

collect_diff(_Diff, nocollect, Data) ->
    Data;
collect_diff(Diff, collect, Data={S,T,_}) ->
    Data2 = erlang:setelement(1, Data, S+Diff),
    erlang:setelement(2, Data2, T+1).

collect_flush(_Flushed, nocollect, Data) ->
    Data;
collect_flush(Flushed, collect, Data={_,_,F}) ->
    erlang:setelement(3, Data, F+Flushed).
