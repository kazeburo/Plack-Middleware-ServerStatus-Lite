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
    plan tests => scalar @servers * 2;
}

my $accesses = 0;
my $bytes = 0;
my $response_string = "Hello World"x2_000;
my $response_length = length($response_string);

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
        sub { [200, [ 'Content-Type' => 'text/plain' ], [ $response_string ]] };
    };

    test_tcp(
        client => sub {
            my $port = shift;

            my $ua = LWP::UserAgent->new;
            my $max = 14;
            for ( 1..$max ) {
                $ua->get("http://localhost:$port/");
                $bytes += $response_length;
            }

            my $res = $ua->get("http://localhost:$port/server-status");
            $accesses += $max; # this hasn't counted the current hit yet
            $bytes += 100; # ballpark, doesn't matter
            my $total_kbytes = int($bytes / 1_000);
            like $res->content, qr/Total Accesses: $accesses/;
            like $res->content, qr/Total Kbytes: $total_kbytes/;
            $accesses += 1;  # count the current hit for the next time around
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
