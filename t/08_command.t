use strict;
use Test::More;
use Test::TCP;
use LWP::UserAgent;
use Plack::Builder;
use Plack::Loader;
use File::Temp;
use Capture::Tiny qw/capture/;
use File::Spec;

my $dir = File::Temp::tempdir( CLEANUP => 1 );
my ($fh, $filename) = File::Temp::tempfile( UNLINK=>1, EXLOCK=>0 );
my $body = "Hello World" x 2048;
my $body_len = length $body;

my $app = builder {
    enable 'ServerStatus::Lite', 
        path => '/server-status',
        allow=> [ '0.0.0.0/0', '::/0' ],
        scoreboard => $dir,
        counter_file => $filename;
    sub { 
        my $env = shift; 
        sleep 3 if $env->{PATH_INFO} eq '/sleep';
        [200, [ 'Content-Type' => 'text/plain' ], [ $body ]]
    };
};

test_tcp(
    client => sub {
        my $port = shift;

        my $pid = fork;
        if ( $pid ) {
            sleep 1;
            my ($stdout, $stderr, $exit) = capture {
                system( $^X, File::Spec->catfile('bin','server-status'),'--scoreboard',$dir,'--counter',$filename );
            };
            is $exit, 0, 'exit code';
            like $stdout, qr/IdleWorkers: 4/;
            like $stdout, qr/BusyWorkers: 1/;
        }
        elsif ( defined $pid ) {
            # slow response
            my $ua = LWP::UserAgent->new;
            my $res = $ua->get("http://localhost:$port/sleep");
            is($res->content, $body);
            exit;
        }
        waitpid( $pid, 0);

        my $ua = LWP::UserAgent->new;
        my $max = 14;
        for ( 1..$max ) {
            my $res = $ua->get("http://localhost:$port/");
            is($res->content, $body);
        }

        my ($stdout, $stderr, $exit) = capture {
            system( $^X, File::Spec->catfile('bin','server-status'), '--scoreboard',$dir,'--counter',$filename );
        };
        is $exit, 0, 'exit code';
        my $accesss = $max +1;
        like $stdout, qr/Total Accesses: $accesss/;
        my $kbyte = int( $body_len * $accesss / 1_000 );
        like $stdout, qr/Total Kbytes: $kbyte/;
        
    },
    server => sub {
        my $port = shift;
        my $loader = Plack::Loader->load(
            'Starman',
            host => 'localhost',
            port => $port,
            workers => 5,
        );
        $loader->run($app);
        exit;
    },
);

done_testing;

