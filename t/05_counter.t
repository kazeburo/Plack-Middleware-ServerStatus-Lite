use strict;
use Test::More;
use Test::TCP;
use LWP::UserAgent;
use Plack::Builder;
use Plack::Loader;
use File::Temp;

if ( ! eval { require Cache::FastMmap; 1 } ) {
    plan skip_all => 'Cache::FastMmap isnot installed';
}

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
    plan tests => scalar @servers;
}

for my $server ( @servers ) {
    warn "using $server for test";

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    my ($fh, $filename) = File::Temp::tempfile( UNLINK=>1, EXLOCK=>0 );

    my $app = builder {
        enable 'ServerStatus::Lite', 
            path => '/server-status',
            allow=>'0.0.0.0/0',
            scoreboard => $dir,
            counter_file => $filename;
        sub { [200, [ 'Content-Type' => 'text/plain' ], [ "Hello World" ]] };
    };

    test_tcp(
        client => sub {
            my $port = shift;

            my $ua = LWP::UserAgent->new;
            my $max = 14;
            for ( 1..$max ) {
                $ua->get("http://localhost:$port/");
            }

            my $res = $ua->get("http://localhost:$port/server-status");
            my $accesss = $max+1;
            like $res->content, qr/Total Accesses: $accesss/;
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
        },
    );

}
