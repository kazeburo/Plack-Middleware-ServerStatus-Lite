package Plack::Middleware::ServerStatus::Lite;

use strict;
use warnings;
use parent qw(Plack::Middleware);
use Plack::Util::Accessor qw(path allow);
use Net::CIDR::Lite;

our $VERSION = 0.01;

sub prepare_app {
    my $self = shift;
    
    if ( $self->allow ) {
        my $cidr = Net::CIDR::Lite->new();
        my @ip = ref $self->allow ? @{$self->allow} : ($self->allow);
        $cidr->add_any( $_ ) for @ip;
        $self->{__cidr} = $cidr;
    }
}

sub call {
    my ($self, $env) = @_;

    $self->set_state("A", $env);

    my $res;
    if( $self->path && $env->{PATH_INFO} eq $self->path ) {
        $res = $self->_handle_server_status($env);
    }
    else {
        $res = $self->app->($env);
    }

    $self->set_state("_");

    return $res;
}

my $prev='';
sub set_state {
    my $self = shift;
    my $status = shift || '_';
    my $env = shift;
    if ( $env ) {
        $prev = join(" ", $env->{REMOTE_ADDR}, $env->{HTTP_HOST}, $env->{REQUEST_METHOD}, $env->{REQUEST_URI}, $env->{SERVER_PROTOCOL});
    }
    $0 = sprintf("server-status-lite[%s] %s %s",getppid, $status, $prev);
}

sub _handle_server_status {
    my ($self, $env ) = @_;

    if ( ! $self->allowed($env->{REMOTE_ADDR}) ) {
        return [403, ['Content-Type' => 'text/plain'], [ 'Forbidden' ]];
    }

    my $ps = `LC_ALL=C command ps -o ppid,pid,command`;
    $ps =~ s/^\s+//mg;

    my $parent = getppid;
    my $idle = 0;
    my $busy = 0;
    for my $line (split /\n/, $ps) {
        my ($ppid, $pid, $command) = split /\s+/, $line, 3;
        next if $ppid =~ /\D/ || $ppid != $parent;
        if ( $command =~ /^server-status-lite\[\d+\]\sA\s/ ) {
            $busy++;
        }
        else {
            $idle++;
        }
    }

    return [200, ['Content-Type' => 'text/plain'], [ 
        "BusyWorkers: $busy\n",
        "IdleWorkers: $idle\n",
    ]];
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
