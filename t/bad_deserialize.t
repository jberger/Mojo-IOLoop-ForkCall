use Mojo::Base -strict;

use Mojo::IOLoop::ForkCall;

use Test::More;

my ($err, $res);
my $fc = Mojo::IOLoop::ForkCall->new(sub{'Lived'});
$fc->on(finish => sub { my $fc = shift; $err = shift; $res = shift; $fc->ioloop->stop });
$fc->start;
$fc->ioloop->start;

ok ! $err;
is $res, 'Lived';

$fc->deserializer(sub{ die "Died\n" });
$fc->start;
$fc->ioloop->start;

chomp $err;
is $err, 'Died';
ok ! $res;

done_testing;

