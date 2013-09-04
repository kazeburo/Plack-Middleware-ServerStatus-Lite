use Plack::Builder;

builder {
    enable "Plack::Middleware::ServerStatus::Lite",
        path => '/server-status',
        allow => [ '127.0.0.1','::ffff:127.0.0.1'],
        scoreboard => '/tmp/server-status',
        counter_file => '/tmp/server-status/counter';
    sub { [200,[],["ok"]] };
};



