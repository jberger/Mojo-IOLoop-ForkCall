use Mojo::Base -strict;
use Mojo::IOLoop::ForkCall;

use Test::More;
use Devel::Peek 'SvREFCNT';

my $fc = Mojo::IOLoop::ForkCall->new(weaken => 1);

my $res;
$fc->run(sub{ sleep 2; return shift }, ['Done'], sub {
  my ($fc, $err, $r) = @_;
  $res = $r;
  $fc->ioloop->stop;
});
is SvREFCNT($fc), 1, 'ForkCall instance has correct ref count';

$fc->ioloop->start;

is $res, 'Done', 'got correct response';

done_testing;

