use Test::More;

use Mojo::Base -strict;
use Mojo::IOLoop;
use Mojo::IOLoop::ForkCall;

my $tick = 0;
Mojo::IOLoop->recurring( 1 => sub { $tick++ } );

my @res;
fork_call { sleep 3; return 'good', ['test'] } sub { @res = @_; Mojo::IOLoop->stop; };
Mojo::IOLoop->start;

ok $tick, 'Main process not blocked';
is_deeply \@res, ['good', ['test']], 'return value correct';

done_testing;

