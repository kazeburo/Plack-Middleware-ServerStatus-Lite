package Plack::Middleware::ServerStatus::Lite;

use strict;
use warnings;
use parent qw(Plack::Middleware);
use Plack::Util::Accessor qw(scoreboard path allow counter_file);
use Parallel::Scoreboard;
use Net::CIDR::Lite;
use Try::Tiny;
use JSON;
use Fcntl qw(:DEFAULT :flock);
use IO::Handle;

our $VERSION = '0.07';

sub prepare_app {
    my $self = shift;
    $self->{uptime} = time;

    if ( $self->allow ) {
        my $cidr = Net::CIDR::Lite->new();
        my @ip = ref $self->allow ? @{$self->allow} : ($self->allow);
        $cidr->add_any( $_ ) for @ip;
        $self->{__cidr} = $cidr;
    }

    if ( $self->scoreboard ) {
        my $scoreboard = Parallel::Scoreboard->new(
            base_dir => $self->scoreboard
        );
        $self->{__scoreboard} = $scoreboard;
    }

}

sub call {
    my ($self, $env) = @_;

    $self->set_state("A", $env);

    if ( $self->counter_file ) {
        $self->counter(1);
    }

    my $res;
    try {
        if( $self->path && $env->{PATH_INFO} eq $self->path ) {
            $res = $self->_handle_server_status($env);
            $self->set_state("_");
        }
        else {
            my $app_res = $self->app->($env);

            if ( ref $app_res eq 'ARRAY' ) {
                $res = $app_res;
                $self->set_state("_");
            }
            else {
                $res = sub {
                    my $respond = shift;

                    my $writer;
                    try {
                        $app_res->(sub { return $writer = $respond->(@_) });
                    } catch {
                        if ($writer) {
                            $writer->close;
                        }
                        die $_;
                    } finally {
                        $self->set_state("_");
                    };
                };
            }
        }
    } catch {
        $self->set_state("_");
        die $_;
    };
    return $res;
}

my $prev='';
sub set_state {
    my $self = shift;
    return if !$self->{__scoreboard};

    my $status = shift || '_';
    my $env = shift;
    if ( $env ) {
        no warnings 'uninitialized';
        $prev = join(" ", $env->{REMOTE_ADDR}, $env->{HTTP_HOST} || '', 
                          $env->{REQUEST_METHOD}, $env->{REQUEST_URI}, $env->{SERVER_PROTOCOL}, time);
    }
    $self->{__scoreboard}->update(
        sprintf("%s %s",$status, $prev)
    );
}

sub _handle_server_status {
    my ($self, $env ) = @_;

    if ( ! $self->allowed($env->{REMOTE_ADDR}) ) {
        return [403, ['Content-Type' => 'text/plain'], [ 'Forbidden' ]];
    }

    my $upsince = time - $self->{uptime};
    my $duration = "";
    my @spans = (86400 => 'days', 3600 => 'hours', 60 => 'minutes');
    while (@spans) {
        my ($seconds,$unit) = (shift @spans, shift @spans);
        if ($upsince > $seconds) {
            $duration .= int($upsince/$seconds) . " $unit, ";
            $upsince = $upsince % $seconds;
        }
    }
    $duration .= "$upsince seconds";

    my $body="Uptime: $self->{uptime} ($duration)\n";
    my %stats = ( 'Uptime' => $self->{uptime} );

    if ( $self->counter_file ) {
        my $counter = $self->counter;
        $body .= sprintf "Total Accesses: %s\n", $counter;
        $stats{TotalAccesses} = $counter;
    }

    if ( my $scoreboard = $self->{__scoreboard} ) {
        my $stats = $scoreboard->read_all();
        my $raw_stats='';
        my $idle = 0;
        my $busy = 0;

        my $parent_pid = getppid;
        my $ps = `LC_ALL=C command ps -e -o ppid,pid`;
        $ps =~ s/^\s+//mg;
        my @all_workers;
        for my $line ( split /\n/, $ps ) {
            next if $line =~ m/^\D/;
            my ($ppid, $pid) = split /\s+/, $line, 2;
            push @all_workers, $pid if $ppid == $parent_pid;
        }

        my @raw_stats;
        for my $pid ( @all_workers  ) {
            if ( exists $stats->{$pid} && $stats->{$pid} =~ m!^A! ) {
                $busy++;
            }
            else {
                $idle++;
            }

            my @pstats = split /\s/, ($stats->{$pid} || '.');
            $pstats[6] = time - $pstats[6] if defined $pstats[6];
            $raw_stats .= sprintf "%s %s\n", $pid, join(" ", @pstats);
            push @raw_stats, {
                pid => $pid,
                status => defined $pstats[0] ? $pstats[0] : undef, 
                remote_addr => defined $pstats[1] ? $pstats[1] : undef,
                host => defined $pstats[2] ? $pstats[2] : undef,
                method => defined $pstats[3] ? $pstats[3] : undef,
                uri => defined $pstats[4] ? $pstats[4] : undef,
                protocol => defined $pstats[5] ? $pstats[5] : undef,
                ss => defined $pstats[6] ? $pstats[6] : undef
            };
        }
        $body .= <<EOF;
BusyWorkers: $busy
IdleWorkers: $idle
--
pid status remote_addr host method uri protocol ss
$raw_stats
EOF
        $stats{BusyWorkers} = $busy;
        $stats{IdleWorkers} = $idle;
        $stats{stats} = \@raw_stats;
    }
    else {
       $body .= "WARN: Scoreboard has been disabled\n";
       $stats{WARN} = 'Scoreboard has been disabled';
    }
    if ( ($env->{QUERY_STRING} || '') =~ m!\bjson\b!i ) {
        return [200, ['Content-Type' => 'application/json; charset=utf-8'], [ JSON::encode_json(\%stats) ]];
    }
    return [200, ['Content-Type' => 'text/plain'], [ $body ]];
}

sub allowed {
    my ( $self , $address ) = @_;
    return unless $self->{__cidr};
    return $self->{__cidr}->find( $address );
}

sub counter {
    my $self = shift;
    my $parent_pid = getppid;
    if ( ! $self->{__counter} ) {
        sysopen( my $fh, $self->counter_file, O_CREAT|O_RDWR ) or die "cannot open counter_file: $!";
        autoflush $fh 1;
        $self->{__counter} = $fh;
        flock $fh, LOCK_EX;
        my $len = sysread $fh, my $buf, 10;
        if ( !$len || $buf != $parent_pid ) {
            seek $fh, 0, 0;
            syswrite $fh, sprintf("%-10d%-20d", $parent_pid, 0);
        } 
        flock $fh, LOCK_UN;
    }
    if ( @_ ) {
        my $fh = $self->{__counter};
        flock $fh, LOCK_EX;
        seek $fh, 10, 0;
        sysread $fh, my $counter, 20;
        $counter++;
        seek $fh, 0, 0;
        syswrite $fh, sprintf("%-10d%-20d", $parent_pid, $counter);
        flock $fh, LOCK_UN;
        return $counter;
    }
    else {
        my $fh = $self->{__counter};
        flock $fh, LOCK_EX;
        seek $fh, 10, 0;
        sysread $fh, my $counter, 20;
        flock $fh, LOCK_UN;
        return $counter + 0;
    }
}

1;
__END__

=head1 NAME

Plack::Middleware::ServerStatus::Lite - show server status like Apache's mod_status

=head1 SYNOPSIS

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

=head1 DESCRIPTION

Plack::Middleware::ServerStatus::Lite is a middleware that display server status in multiprocess Plack servers such as Starman and Starlet. This middleware changes status only before and after executing the application. so cannot monitor keepalive session and network i/o wait. 

=head1 CONFIGURATIONS

=over 4

=item path

  path => '/server-status',

location that displays server status

=item allow

  allow => '127.0.0.1'
  allow => ['192.168.0.0/16', '10.0.0.0/8']

host based access control of a page of server status

=item scoreboard

  scoreboard => '/path/to/dir'

Scoreboard directory, Middleware::ServerStatus::Lite stores processes activity information in

=item counter_file

  counter_file => '/path/to/counter_file'

Enable Total Access counter

=back

=head1 WHAT DOES "SS" MEAN IN STATUS

Seconds since beginning of most recent request

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo {at} gmail.comE<gt>

=head1 SEE ALSO

Original ServerStatus by cho45 <http://github.com/cho45/Plack-Middleware-ServerStatus>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
