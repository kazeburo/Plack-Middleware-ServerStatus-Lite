requires 'JSON', '2.53';
requires 'Net::CIDR::Lite';
requires 'Parallel::Scoreboard', '0.02';
requires 'Plack::Middleware';
requires 'Try::Tiny', '0.09';
requires 'parent';

on build => sub {
    requires 'ExtUtils::MakeMaker', '6.36';
    requires 'Test::More';
    requires 'Test::TCP';
};
