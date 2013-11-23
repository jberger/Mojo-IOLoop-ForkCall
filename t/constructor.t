use Mojo::Base -strict;

use Test::More;
use Mojo::IOLoop::ForkCall;

my $job = sub { 'job' };
my $cb  = sub { 'cb'  };

sub verify {
  local $Test::Builder::Level = $Test::Builder::Level + 1; 
  my $fc = shift;
  is $fc->job, $job, 'correct job';
  is_deeply $fc->subscribers('finish'), [$cb], 'correct finish handler';
}

subtest 'Standard' => sub {
  my $fc = Mojo::IOLoop::ForkCall->new( job => $job );
  $fc->on( finish => $cb );
  verify( $fc );
};

subtest 'One subref' => sub {
  my $fc = Mojo::IOLoop::ForkCall->new( $job );
  $fc->on( finish => $cb );
  verify( $fc );
};

subtest 'Two subrefs' => sub {
  my $fc = Mojo::IOLoop::ForkCall->new( $job, $cb );
  verify( $fc );
};

subtest 'Pairs plus finish cb' => sub {
  my $fc = Mojo::IOLoop::ForkCall->new( job => $job, $cb );
  verify( $fc );
};

done_testing;

