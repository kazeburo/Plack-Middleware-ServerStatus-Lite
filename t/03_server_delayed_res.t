use strict;
use Test::More;
use Test::TCP;
use LWP::UserAgent;
use Plack::Builder;
use Plack::Loader;
use File::Temp;

my @servers;
for my $server ( qw/Starman Starlet/ ) {
    my $installed = 0;
    eval {
        require 'Plack/Handler/'.$server.'.pm';
        $installed = 1;
    };
    if ( $installed ) {
        push @servers, $server;
    }
}
if ( !@servers ) {
    plan skip_all => 'Starlet or Starman isnot installed';
}
else {
    plan tests => 6 * scalar @servers;
}


for my $server ( @servers ) {
    warn "using $server for test";

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    my $app = builder {
        enable 'ServerStatus::Lite', path => '/server-status', allow=>[ '0.0.0.0/0', '::/0' ], scoreboard => $dir;
        sub {
            sub {
                sleep 3;
                shift->([200, [ 'Content-Type' => 'text/plain' ],['Hello World']]);
            };
        };
    };

    test_tcp(
        client => sub {
            my $port = shift;
            my $pid = fork;
            if ( $pid ) {
                sleep 1;
                my $ua = LWP::UserAgent->new;
                my $res = $ua->get("http://localhost:$port/server-status");
                like( $res->content, qr/IdleWorkers: 3/ );
                like( $res->content, qr/BusyWorkers: 2/ );
                like( $res->content, qr/Uptime: \d+ \(\d seconds\)/ );
            }
            elsif ( defined $pid ) {
                # slow response
                my $ua = LWP::UserAgent->new;
                my $res = $ua->get("http://localhost:$port/");
                exit;
            }
            waitpid( $pid, 0);
        },
        server => sub {
            my $port = shift;
            my $loader;
            if ( $server eq 'Starman' ) {
                $loader = Plack::Loader->load(
                    $server,
                    host => 'localhost',
                    port => $port,
                    workers => 5,
                );
            }
            elsif ( $server eq 'Starlet' ) {
                $loader = Plack::Loader->load(
                    $server,
                    port => $port,
                    max_workers => 5,
                );
            }
            $loader->run($app);
            exit;
        },
    );
}

for my $server ( @servers ) {
    warn "using $server for test";

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    my $app = builder {
        enable 'ServerStatus::Lite', path => '/server-status', allow=>[ '0.0.0.0/0', '::/0' ], scoreboard => $dir;
        sub {
            sub {
                sleep 3;
                my $respond = shift;
                my $writer = $respond->([200, [ 'Content-Type' => 'text/plain' ]]);
                $writer->write("Hello World");
                $writer->close;
            };
        };
    };

    test_tcp(
        client => sub {
            my $port = shift;
            my $pid = fork;
            if ( $pid ) {
                sleep 1;
                my $ua = LWP::UserAgent->new;
                my $res = $ua->get("http://localhost:$port/server-status");
                like( $res->content, qr/IdleWorkers: 3/ );
                like( $res->content, qr/BusyWorkers: 2/ );
                like( $res->content, qr/Uptime: \d+ \(\d seconds\)/ );
            }
            elsif ( defined $pid ) {
                # slow response
                my $ua = LWP::UserAgent->new;
                my $res = $ua->get("http://localhost:$port/");
                exit;
            }
            waitpid( $pid, 0);
        },
        server => sub {
            my $port = shift;
            my $loader;
            if ( $server eq 'Starman' ) {
                $loader = Plack::Loader->load(
                    $server,
                    host => 'localhost',
                    port => $port,
                    workers => 5,
                );
            }
            elsif ( $server eq 'Starlet' ) {
                $loader = Plack::Loader->load(
                    $server,
                    port => $port,
                    max_workers => 5,
                );
            }
            $loader->run($app);
            exit;
        },
    );
}
