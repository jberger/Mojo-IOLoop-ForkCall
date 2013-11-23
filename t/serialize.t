use Mojo::Base -strict;

use lib 'lib';
use Mojo::IOLoop::ForkCall;
use Storable ();
use Test::More;

my $fc = Mojo::IOLoop::ForkCall->new(sub{'Lived'});

my $received;
$fc->serialize(sub{my $f = Storable::freeze($_[0]); diag "sending: $f"; $f});
$fc->deserialize(sub{$received = $_[0]; Storable::thaw($_[0])});

my ($err, @res);
$fc->on(finish => sub{
  my $fc = shift;
  $err = shift;
  @res = @_;
  $fc->ioloop->stop;
});

$fc->start;
$fc->ioloop->start;

ok $received, 'received something from child' and diag "got: $received";
is_deeply \@res, ['Lived'] or diag 'error: '.$err;

done_testing;

