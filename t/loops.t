use Mojo::Base -strict;

use Mojo::IOLoop;
use Mojo::IOLoop::ForkCall;
use Test::More;

my $fc = Mojo::IOLoop::ForkCall->new;

my ($err, $res);
Mojo::IOLoop->next_tick(sub{
  $fc->run(
    sub{
      my $i = 0;
      Mojo::IOLoop->next_tick(sub{$i++; Mojo::IOLoop->stop});
      Mojo::IOLoop->start;
      return $i;
    },
    sub{
      (undef, $err, $res) = @_;
      Mojo::IOLoop->stop;
    }
  );
});

Mojo::IOLoop->start;
ok ! $err, 'no error';
ok $res, 'child loop ran';

done_testing;

