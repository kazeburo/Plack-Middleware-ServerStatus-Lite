package Plack::Middleware::ServerStatus::Lite;

use strict;
use warnings;
use parent qw(Plack::Middleware);
use Plack::Util::Accessor qw(scoreboard path allow counter_file skip_ps_command);
use Plack::Util;
use Parallel::Scoreboard;
use Net::CIDR::Lite;
use Try::Tiny;
use JSON;
use Fcntl qw(:DEFAULT :flock);
use IO::Handle;

our $VERSION = '0.31';

my $JSON = JSON->new->utf8(0);

sub prepare_app {
    my $self = shift;
    $self->{uptime} = time;

    if ( $self->allow ) {
        my @ip = ref $self->allow ? @{$self->allow} : ($self->allow);
        my @ipv4;
        my @ipv6;
        for (@ip) {
            # hacky check, but actual checks are done in Net::CIDR::Lite.
            if (/:/) {
                push @ipv6, $_;
            } else {
                push @ipv4, $_;
            }
        }
        if ( @ipv4 ) {
            my $cidr4 = Net::CIDR::Lite->new();
            $cidr4->add_any($_) for @ipv4;
            $self->{__cidr4} = $cidr4;
        }
        if ( @ipv6 ) {
            my $cidr6 = Net::CIDR::Lite->new();
            $cidr6->add_any($_) for @ipv6;
            $self->{__cidr6} = $cidr6;
        }
    }
    else {
        warn "[Plack::Middleware::ServerStatus::Lite] 'allow' is not provided. Any host will not be able to access server-status page.\n";
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
    my $back_state = sub {
        $self->set_state("_");
    };
    my $guard = bless $back_state, 'Plack::Middleware::ServerStatus::Lite::Guard';

    if( $self->path && $env->{PATH_INFO} eq $self->path ) {
        my $res = $self->_handle_server_status($env);
        if ( $self->counter_file ) {
            my $length = Plack::Util::content_length($res->[2]);
            $self->counter(1,$length);
        }
        return $res;
    }

    my $res = $self->app->($env);
    Plack::Util::response_cb($res, sub {
        my $res = shift;

        if ( defined $res->[2] ) {
            if ( $self->counter_file ) {
                my $length = Plack::Util::content_length($res->[2]);
                $self->counter(1,$length);
            }
            undef $guard;
            return ;
        }

        my $length = 0;
        return sub {
            my $chunk = shift;
            if ( ! defined $chunk ) {
                if ( $self->counter_file ) {
                    $self->counter(1,$length);
                }
                undef $guard;
                return;
            }
            $length += length($chunk); 
            return $chunk;
        };
    });
}

my $prev={};
sub set_state {
    my $self = shift;
    return if !$self->{__scoreboard};

    my $status = shift || '_';
    my $env = shift;
    if ( $env ) {
        no warnings 'uninitialized';
        $prev = {
            remote_addr => $env->{REMOTE_ADDR},
            host => defined $env->{HTTP_HOST} ? $env->{HTTP_HOST} : '-',
            method => $env->{REQUEST_METHOD},
            uri => $env->{REQUEST_URI},
            protocol => $env->{SERVER_PROTOCOL},
            time => time(),
        };
    }
    $self->{__scoreboard}->update($JSON->encode({
        %{$prev},
        pid => $$,
        ppid => getppid(),
        uptime => $self->{uptime},
        status => $status,
    }));
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
    my %status = ( 'Uptime' => $self->{uptime} );

    if ( $self->counter_file ) {
        my ($counter,$bytes) = $self->counter;
        my $kbytes = int($bytes / 1_000);
        $body .= sprintf "Total Accesses: %s\n", $counter;
        $body .= sprintf "Total Kbytes: %s\n", $kbytes;
        $status{TotalAccesses} = $counter;
        $status{TotalKbytes} = $kbytes;
    }

    if ( my $scoreboard = $self->{__scoreboard} ) {
        my $stats = $scoreboard->read_all();
        my $idle = 0;
        my $busy = 0;

        my @all_workers = ();
        my $parent_pid = getppid;
        
        if ( $self->skip_ps_command ) {
            # none
            @all_workers = keys %$stats;
        }
        elsif ( $^O eq 'cygwin' ) {
            my $ps = `ps -ef`;
            $ps =~ s/^\s+//mg;
            for my $line ( split /\n/, $ps ) {
                next if $line =~ m/^\D/;
                my @proc = split /\s+/, $line;
                push @all_workers, $proc[1] if $proc[2] == $parent_pid;
            }
        }
        elsif ( $^O !~ m!mswin32!i ) {
            my $psopt = $^O =~ m/bsd$/ ? '-ax' : '-e';
            my $ps = `LC_ALL=C command ps $psopt -o ppid,pid`;
            $ps =~ s/^\s+//mg;
            for my $line ( split /\n/, $ps ) {
                next if $line =~ m/^\D/;
                my ($ppid, $pid) = split /\s+/, $line, 2;
                push @all_workers, $pid if $ppid == $parent_pid;
            }
        }
        else {
            # todo windows?
            @all_workers = keys %$stats;
        }

        my $process_status = '';
        my @process_status;
        for my $pid ( @all_workers  ) {
            my $json = $stats->{$pid};
            my $pstatus = eval { 
                $JSON->decode($json || '{}');
            };
            $pstatus ||= {};
            if ( $pstatus->{status} && $pstatus->{status} eq 'A' ) {
                $busy++;
            }
            else {
                $idle++;
            }

            if ( defined $pstatus->{time} ) {
                $pstatus->{ss} = time - $pstatus->{time};
            }
            $pstatus->{pid} ||= $pid;
            delete $pstatus->{time};
            delete $pstatus->{ppid};
            delete $pstatus->{uptime};
            $process_status .= sprintf "%s\n", 
                join(" ", map { defined $pstatus->{$_} ? $pstatus->{$_} : '' } qw/pid status remote_addr host method uri protocol ss/);
            push @process_status, $pstatus;
        }
        $body .= <<EOF;
BusyWorkers: $busy
IdleWorkers: $idle
--
pid status remote_addr host method uri protocol ss
$process_status
EOF
        chomp $body;
        $status{BusyWorkers} = $busy;
        $status{IdleWorkers} = $idle;
        $status{stats} = \@process_status;
    }
    else {
       $body .= "WARN: Scoreboard has been disabled\n";
       $status{WARN} = 'Scoreboard has been disabled';
    }
    if ( ($env->{QUERY_STRING} || '') =~ m!\bjson\b!i ) {
        return [200, ['Content-Type' => 'application/json; charset=utf-8'], [ JSON::encode_json(\%status) ]];
    }
    return [200, ['Content-Type' => 'text/plain'], [ $body ]];
}

sub allowed {
    my ( $self , $address ) = @_;
    if ( $address =~ /:/) {
        return unless $self->{__cidr6};
        return $self->{__cidr6}->find( $address );
    }
    return unless $self->{__cidr4};
    return $self->{__cidr4}->find( $address );
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
            syswrite $fh, sprintf("%-10d%-20d%-20d", $parent_pid, 0, 0);
        } 
        flock $fh, LOCK_UN;
    }
    if ( @_ ) {
        my ($count, $bytes) = @_;
        $count ||= 1;
        $bytes ||= 0;
        my $fh = $self->{__counter};
        flock $fh, LOCK_EX;
        seek $fh, 10, 0;
        sysread $fh, my $buf, 40;
        my $counter = substr($buf, 0, 20);
        my $total_bytes = substr($buf, 20, 20);
        $counter ||= 0;
        $total_bytes ||= 0;
        $counter += $count;
        if ($total_bytes + $bytes > 2**53){ # see docs
            $total_bytes = 0;
        } else {
            $total_bytes += $bytes;
        }
        seek $fh, 0, 0;
        syswrite $fh, sprintf("%-10d%-20d%-20d", $parent_pid, $counter, $total_bytes);
        flock $fh, LOCK_UN;
        return $counter;
    }
    else {
        my $fh = $self->{__counter};
        flock $fh, LOCK_EX;
        seek $fh, 10, 0;
        sysread $fh, my $counter, 20;
        sysread $fh, my $total_bytes, 20;
        flock $fh, LOCK_UN;
        return $counter + 0, $total_bytes + 0;
    }
}

1;

package 
    Plack::Middleware::ServerStatus::Lite::Guard;

sub DESTROY {
    $_[0]->();
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

host based access control of a page of server status. supports IPv6 address.

=item scoreboard

  scoreboard => '/path/to/dir'

Scoreboard directory, Middleware::ServerStatus::Lite stores processes activity information in

=item counter_file

  counter_file => '/path/to/counter_file'

Enable Total Access counter

=item skip_ps_command

  skip_ps_command => 1 or 0

ServerStatus::Lite executes `ps command` to find all worker processes. But in some systems
that does not mount "/proc" can not find any processes.
IF 'skip_ps_command' is true, ServerStatus::Lite does not `ps`, and checks only processes that
already did process requests.

=back

=head1 TOTAL BYTES

The largest integer that 32-bit Perl can store without loss of precision
is 2**53. So rather than getting all fancy with Math::BigInt, we're just
going to be conservative and wrap that around to 0. That's enough to count
1 GB per second for a hundred days.

=head1 WHAT DOES "SS" MEAN IN STATUS

Seconds since beginning of most recent request

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo {at} gmail.comE<gt>

=head1 SEE ALSO

Original ServerStatus by cho45 <http://github.com/cho45/Plack-Middleware-ServerStatus>

L<Plack::Middleware::ServerStatus::Tiny>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
