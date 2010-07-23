package Plack::Middleware::ServerStatus::Lite;

use strict;
use warnings;
use parent qw(Plack::Middleware);
use Plack::Util::Accessor qw(scoreboard path allow);
use Parallel::Scoreboard;
use Net::CIDR::Lite;
use Try::Tiny;

our $VERSION = 0.01;

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

    try {
        if( $self->path && $env->{PATH_INFO} eq $self->path ) {
            $self->_handle_server_status($env);
        }
        else {
            $self->app->($env);
        }
    } catch {
        die $_;
    } finally {
        $self->set_state("_");
    };
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
                          $env->{REQUEST_METHOD}, $env->{REQUEST_URI}, $env->{SERVER_PROTOCOL});
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

    my $body="Uptime: $self->{uptime}\n";
    if ( my $scoreboard = $self->{__scoreboard} ) {
        my $stats = $scoreboard->read_all();
        my $raw_stats='';
        my $idle = 0;
        my $busy = 0;

        for my $pid ( sort { $a <=> $b } keys %$stats) {
            if ( $stats->{$pid} =~ m!^A! ) {
                $busy++;
            }
            else {
                $idle++;
            }
            $raw_stats .= sprintf "%s %s\n", $pid, $stats->{$pid};
        }
        $body .= <<EOF;
BusyWorkers: $busy
IdleWorkers: $idle
--
pid status remote_addr host method uri protocol
$raw_stats
EOF
    }
    else {
       $body .= "WARN: Scoreboard has been disabled\n";

    }
    return [200, ['Content-Type' => 'text/plain'], [ $body ]];
}

sub allowed {
    my ( $self , $address ) = @_;
    return unless $self->{__cidr};
    return $self->{__cidr}->find( $address );
}


1;
__END__

=head1 NAME

Plack::Middleware::ServerStatus::Lite - how server status like Apache's mod_status

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
      enable "Plack::Middleware::ServerStatus::Lite",
          path => '/server-status',
          allow => [ '127.0.0.1', '192.168.0.0/16' ];
      $app;
  };

=head1 DESCRIPTION

Plack::Middleware::ServerStatus::Lite is ..

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo {at} gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
