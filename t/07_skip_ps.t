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
    plan tests => 3 * scalar @servers;
}


for my $server ( @servers ) {
    warn "using $server for test";

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    my $app = builder {
        enable 'ServerStatus::Lite',
            path => '/server-status',
            allow=> [ '0.0.0.0/0', '::/0' ],
            scoreboard => $dir,
            skip_ps_command => 1;
        sub { sleep 3; [200, [ 'Content-Type' => 'text/plain' ], [ "Hello World" ]] };
    };

    test_tcp(
        client => sub {
            my $port = shift;
            sleep 1;
            my $ua = LWP::UserAgent->new;
            my $res = $ua->get("http://localhost:$port/server-status");
            like( $res->content, qr/IdleWorkers: 0/ );
            like( $res->content, qr/BusyWorkers: 1/ );
            like( $res->content, qr/Uptime: \d+ \(\d seconds\)/ );
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
