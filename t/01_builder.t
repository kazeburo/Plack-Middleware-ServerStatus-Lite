use strict;
use Test::More tests => 4;

use Plack::Builder;
use Plack::Test;
use Plack::Middleware::ServerStatus::Lite;
use File::Temp;
use Test::SharedFork;

my $pid = fork;
if ( $pid ) {
    #parent
}
elsif ( defined $pid ) {
    #child;
    {
        my $app = builder {
            enable 'ServerStatus::Lite', path => '/server-status', allow=>'0.0.0.0/0';
            sub { [200, [ 'Content-Type' => 'text/plain' ], [ "Hello World" ]] };
        };

        test_psgi
            app => $app,
                client => sub {
                    my $cb = shift;
                    my $req = HTTP::Request->new(GET => "http://localhost/server-status");
                    my $res = $cb->($req);
                    like( $res->content, qr/Uptime:/ );
                    unlike( $res->content, qr/IdleWorker/ );
                };
    }
    {
        my $dir = File::Temp::tempdir( CLEANUP => 1 );
        my $app = builder {
            enable 'ServerStatus::Lite', path => '/server-status', allow=>'0.0.0.0/0', scoreboard => $dir;
            sub { [200, [ 'Content-Type' => 'text/plain' ], [ "Hello World" ]] };
        };
        test_psgi
            app => $app,
                client => sub {
                    my $cb = shift;
                    my $req = HTTP::Request->new(GET => "http://localhost/server-status");
                    my $res = $cb->($req);
                    like( $res->content, qr/IdleWorkers: 0/ );
                    like( $res->content, qr/BusyWorkers: 1/ );
                };
    }
    POSIX::_exit(0);
}
else {
    die "failed to fork: $!";
}

waitpid( $pid, 0);
