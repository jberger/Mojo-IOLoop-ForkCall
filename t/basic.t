BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }   

use Mojo::Base -strict;

use Mojo::IOLoop;
use Mojo::IOLoop::ForkCall;
use Test::More;

my $tick = 0;
Mojo::IOLoop->recurring( 0.2 => sub { $tick++ } );

my $fc = Mojo::IOLoop::ForkCall->new;

my @res;
$fc->run( 
  sub { sleep 1; return 'good', \@_ },
  ['test'], 
  sub { @res = @_; Mojo::IOLoop->stop },
);
Mojo::IOLoop->start;
ok $tick, 'main process not blocked';
is_deeply \@res, [ $fc, undef, 'good', ['test']], 'return value correct';

my $err;
$fc->run( 
  sub { die "Died!\n" },
  sub { shift; $err = shift; Mojo::IOLoop->stop },
);
Mojo::IOLoop->start;
chomp $err;
is $err, 'Died!';

done_testing;

