message_load_benchmark
=====

A benchmark that measures the throughput and latency of Erlang message passing.

Usage
-----

    $ erlc message_load_benchmark.erl
    $ erl -noshell -s message_load_benchmark -eval 'init:stop().'

Example Output
--------------

Normal:

```
Starting 96 processes
Warming up (waiting 300000 ms)
Gathering stats (waiting 60000 ms)
Stopping test

== System ==

Linux testing-qa-aws10 5.15.0-1084-aws #91~20.04.1-Ubuntu SMP Fri May 2 06:59:36 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
Erlang/OTP 28 [erts-16.0] [source] [64-bit] [smp:96:96] [ds:96:96:10] [async-threads:1] [jit:ns]
ec2_metadata.instance-type: c7i.metal-24xl

== Parameters ==

Processes = 96
Worker recv wait = 10 ms

== Results ==

NGood = 2406568
Goodput = 40109.46666666667 msg/sec
Latency = 10.894823250371484 us (avg)

NFlush = 72076
Flushput = 1201.2666666666667 msg/sec
```

Pathological:

```
Starting 96 processes
Warming up (waiting 300000 ms)
Gathering stats (waiting 60000 ms)
Stopping test

== System ==

Linux testing-qa-aws10 5.15.0-1084-aws #91~20.04.1-Ubuntu SMP Fri May 2 06:59:36 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
Erlang/OTP 28 [erts-16.0] [source] [64-bit] [smp:96:96] [ds:96:96:10] [async-threads:1] [jit:ns]
ec2_metadata.instance-type: c7i.24xlarge

== Parameters ==

Processes = 96
Worker recv wait = 10 ms

== Results ==

NGood = 337211
Goodput = 5620.183333333333 msg/sec
Latency = 772.3692465548277 us (avg)

NFlush = 244449
Flushput = 4074.1500000000005 msg/sec
```
