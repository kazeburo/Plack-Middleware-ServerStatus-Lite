use inc::Module::Install;
name 'Plack-Middleware-ServerStatus-Lite';
all_from 'lib/Plack/Middleware/ServerStatus/Lite.pm';

# requires '';
requires 'parent';
requires 'Plack::Middleware';
requires 'Net::CIDR::Lite';
requires 'Try::Tiny', 0.09;
requires 'Parallel::Scoreboard', 0.02;
requires 'JSON';

# for for bin/server-status
recommends 'HTTP::Request::Common';
recommends 'HTTP::Response';
recommends 'HTTP::Message::PSGI';
recommends 'Getopt::Long', '2.38';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
test_requires 'Test::TCP';
auto_set_repository;
#auto_include;
WriteAll;

