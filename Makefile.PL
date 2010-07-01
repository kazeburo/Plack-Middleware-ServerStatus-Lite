use inc::Module::Install;
name 'Plack-Middleware-ServerStatus-Lite';
all_from 'lib/Plack/Middleware/ServerStatus/Lite.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
