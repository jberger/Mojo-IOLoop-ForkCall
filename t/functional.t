BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }   

use Mojo::Base -strict;

use Mojo::IOLoop;
use Mojo::IOLoop::ForkCall qw/fork_call/;
use Test::More;

my $tick = 0;
Mojo::IOLoop->recurring( 0.25 => sub { $tick++ } );

my @res;
fork_call { sleep 1; return 'good', @_ } ['test'], sub { @res = @_; Mojo::IOLoop->stop };
Mojo::IOLoop->start;
ok $tick, 'main process not blocked';
is_deeply \@res, ['good', ['test']], 'return value correct';

my $err;
fork_call { die "Died!\n" } sub { $err = $@; Mojo::IOLoop->stop };
Mojo::IOLoop->start;
chomp $err;
is $err, 'Died!';

done_testing;
