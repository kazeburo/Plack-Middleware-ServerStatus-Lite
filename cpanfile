requires 'JSON', '2.53';
requires 'Net::CIDR::Lite';
requires 'Parallel::Scoreboard', '0.03';
requires 'Plack::Middleware';
requires 'Try::Tiny', '0.09';
requires 'parent';
requires 'Getopt::Long', '2.38';
requires 'Pod::Usage';

on 'test' => sub {
    requires 'Test::More';
    requires 'Test::TCP', '2.00';
    requires 'Starman', '0.3013';
    requires 'LWP::UserAgent';
    requires 'Capture::Tiny';
    requires 'Test::SharedFork';
};


