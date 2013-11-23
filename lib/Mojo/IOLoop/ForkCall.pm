package Mojo::IOLoop::ForkCall;

use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01';
$VERSION = eval $VERSION;

use Mojo::IOLoop;
use Child;
use Storable ();

use Exporter 'import';

our @EXPORT_OK = qw/fork_call/;

has 'ioloop' => sub { Mojo::IOLoop->singleton };
has 'job';

sub new { 
  my $class = shift;
  if (@_ == 1 and ref $_[0] eq 'CODE') {
    unshift @_, 'job';
  }
  return $class->SUPER::new(@_);
}

sub start {
  my ($self, @args) = @_;
  my $loop = $self->ioloop;
  my $job = $self->job;

  my $child = Child->new(sub {
    my $parent = shift;

    local $@;
    my $res = eval {
      local $SIG{__DIE__};
      Storable::freeze([undef, $job->(@args)]);
    };
    $res = Storable::freeze([$@]) if $@;
    
    my $w = Mojo::IOLoop::Stream->new($parent->write_handle);
    $loop->stream($w);
    $w->on( close => sub { exit(0) } );
    $w->on( drain => sub { shift->close } );
    $parent->write($res);
  }, pipe => 1);

  my $proc = $child->start;
  my $r = Mojo::IOLoop::Stream->new($proc->read_handle);
  $loop->stream($r);
  $r->on( close => sub { $proc->is_complete || $proc->kill(9); $proc->wait } );
  $r->on( read  => sub { 
    my $res = Storable::thaw($_[1]);
    $self->emit( finish => @$res );
  });
}

sub fork_call (&@) {
  my $cb = pop;
  my ($job, @args) = @_;
  my $fc = __PACKAGE__->new( job => $job );
  $fc->on( finish => sub {
    shift;
    local $@ = shift;
    $cb->(@_);
  });
  $fc->start;
}

1;

