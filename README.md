# NAME

Plack::Middleware::ServerStatus::Lite - show server status like Apache's mod\_status

# SYNOPSIS

    use Plack::Builder;

    builder {
        enable "Plack::Middleware::ServerStatus::Lite",
            path => '/server-status',
            allow => [ '127.0.0.1', '192.168.0.0/16' ],
            counter_file => '/tmp/counter_file',
            scoreboard => '/var/run/server';
        $app;
    };

    % curl http://server:port/server-status
    Uptime: 1234567789
    Total Accesses: 123
    BusyWorkers: 2
    IdleWorkers: 3
    --
    pid status remote_addr host method uri protocol ss
    20060 A 127.0.0.1 localhost:10001 GET / HTTP/1.1 1
    20061 .
    20062 A 127.0.0.1 localhost:10001 GET /server-status HTTP/1.1 0
    20063 .
    20064 .

    # JSON format
    % curl http://server:port/server-status?json
    {"Uptime":"1332476669","BusyWorkers":"2",
     "stats":[
       {"protocol":null,"remote_addr":null,"pid":"78639",
        "status":".","method":null,"uri":null,"host":null,"ss":null},
       {"protocol":"HTTP/1.1","remote_addr":"127.0.0.1","pid":"78640",
        "status":"A","method":"GET","uri":"/","host":"localhost:10226","ss":0},
       ...
    ],"IdleWorkers":"3"}

# DESCRIPTION

Plack::Middleware::ServerStatus::Lite is a middleware that display server status in multiprocess Plack servers such as Starman and Starlet. This middleware changes status only before and after executing the application. so cannot monitor keepalive session and network i/o wait. 

# CONFIGURATIONS

- path

        path => '/server-status',

    location that displays server status

- allow

        allow => '127.0.0.1'
        allow => ['192.168.0.0/16', '10.0.0.0/8']

    host based access control of a page of server status. supports IPv6 address.

- scoreboard

        scoreboard => '/path/to/dir'

    Scoreboard directory, Middleware::ServerStatus::Lite stores processes activity information in

- counter\_file

        counter_file => '/path/to/counter_file'

    Enable Total Access counter



- skip\_ps\_command

        skip_ps_command => 1 or 0

    ServerStatus::Lite executes \`ps command\` to find all worker processes. But in some systems 
    that does not mount "/proc" can not find any processes. 
    IF 'skip\_ps\_command' is true, ServerStatus::Lite does not \`ps\`, and checks only processes that 
    already did process requests.

# TOTAL BYTES

The largest integer that 32-bit Perl can store without loss of precision
is 2\*\*53. So rather than getting all fancy with Math::BigInt, we're just
going to be conservative and wrap that around to 0. That's enough to count
1 GB per second for a hundred days.

# WHAT DOES "SS" MEAN IN STATUS

Seconds since beginning of most recent request

# AUTHOR

Masahiro Nagano <kazeburo {at} gmail.com>

# SEE ALSO

Original ServerStatus by cho45 <http://github.com/cho45/Plack-Middleware-ServerStatus>

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
