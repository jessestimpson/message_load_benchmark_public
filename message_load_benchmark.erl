-module(message_load_benchmark).

-export([start/0]).

-define(NumProcesses, 96).
-define(WarmPeriod, timer:seconds(5*60)).
-define(CollectPeriod, timer:seconds(60)).
-define(TimeUnit, microsecond).
-define(WorkerReceiveWait, 10).

start() ->
    ets:new(?MODULE, [public, named_table]),
    ets:insert(?MODULE, {diff, 0, 0}),
    ets:insert(?MODULE, {flush, 0}),

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
    [ erlang:send(Pid, stop) || {_, Pid} <- Pids ],
    receive_downs(M),
    print_report().

print_report() ->
    [{diff, USum, NS}] = ets:lookup(?MODULE, diff),
    [{flush, NF}] = ets:lookup(?MODULE, flush),

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
    Pid = spawn_link(fun() -> worker_loop(idle, nocollect) end),
    do_start(N-1, [{N, Pid}|Acc]).

worker_loop(idle, Collect) ->
    receive
        start ->
            worker_loop(start, Collect);
        stop ->
            ok;
        collect ->
            worker_loop(idle, collect);
        {Ref, T1} when is_reference(Ref) ->
            T2 = erlang:monotonic_time(?TimeUnit),
            receive_message(Ref, T1, T2, Collect),
            worker_loop(idle, Collect)
    end;
worker_loop(start, Collect) ->
    case select_target() of
        Target when is_pid(Target) ->
            erlang:send_nosuspend(Target, {make_ref(), erlang:monotonic_time(?TimeUnit)});
        _ ->
            ok
    end,
    worker_flush(Collect),
    receive
        stop ->
            ok;
        collect ->
            worker_loop(start, collect);
        {Ref, T1} when is_reference(Ref) ->
            T2 = erlang:monotonic_time(?TimeUnit),
            receive_message(Ref, T1, T2, Collect),
            worker_loop(start, Collect)
    after ?WorkerReceiveWait ->
        worker_loop(start, Collect)
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

receive_message(_Ref, T1, T2, Collect) ->
    case process_info(self(), message_queue_len) of
        {message_queue_len, 0} ->
            Diff = T2 - T1,
            collect_diff(Diff, Collect);
        _ ->
            worker_flush(Collect)
    end.

worker_flush(Collect) ->
    Flushed = do_worker_flush(0),
    collect_flush(Flushed, Collect).

do_worker_flush(N) ->
    receive
        {Ref, _} when is_reference(Ref) ->
            do_worker_flush(N+1)
    after 0 ->
              N
    end.

receive_downs([]) ->
    ok;
receive_downs([M|Rest]) ->
    receive
        {'DOWN', M, process, _Pid, _Reason} ->
            receive_downs(Rest)
    end.

collect_diff(_Diff, nocollect) ->
    ok;
collect_diff(Diff, collect) ->
    ets:update_counter(?MODULE, diff, [{2, Diff}, {3, 1}]).

collect_flush(_Flushed, nocollect) ->
    ok;
collect_flush(Flushed, collect) ->
    ets:update_counter(?MODULE, flush, [{2, Flushed}]).
