package Mojo::IOLoop::ForkCall;

use Mojo::Base -strict;

our $VERSION = '0.01';
$VERSION = eval $VERSION;

use Mojo::IOLoop;
use Child;
use Storable ();

use Exporter 'import';

our @EXPORT = qw/fork_call/;

sub fork_call (&@) {
  my $cb = pop;
  my ($job, @args) = @_;

  my $child = Child->new(sub {
    my $parent = shift;

    local $@;
    my $res = eval {
      local $SIG{__DIE__};
      Storable::freeze([undef, $job->(@args)]);
    };
    $res = Storable::freeze([$@]) if $@;
    
    my $w = Mojo::IOLoop::Stream->new($parent->write_handle);
    Mojo::IOLoop->stream($w);
    $w->on( close => sub { exit(0) } );
    $w->on( drain => sub { shift->close } );
    $parent->write($res);
  }, pipe => 1);

  my $proc = $child->start;
  my $r = Mojo::IOLoop::Stream->new($proc->read_handle);
  Mojo::IOLoop->stream($r);
  $r->on( close => sub { $proc->is_complete || $proc->kill(9); $proc->wait } );
  $r->on( read  => sub { 
    my $res = Storable::thaw($_[1]);
    local $@ = shift @$res;
    $cb->(@$res);
  });
}

1;

