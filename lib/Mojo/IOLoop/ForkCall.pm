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
has 'serialize'   => sub { \&Storable::freeze };
has 'deserialize' => sub { \&Storable::thaw   };

sub new {
  no warnings 'uninitialized';
  my $class = shift;

  # leading arg interpreted as job
  if (ref $_[0] eq 'CODE') {
    unshift @_, 'job';
  }

  # trailing arg interpreted as finish callback
  my $cb;
  if (ref $_[0] eq 'HASH' ||  @_ % 2 and ref $_[-1] eq 'CODE') {
    $cb = pop;
  }

  my $self = $class->SUPER::new(@_);
  $self->on( finish => $cb ) if $cb;
  return $self;
}

sub start {
  my ($self, @args) = @_;
  my $job = $self->job;
  my $serialize = $self->serialize;

  my $child = $self->_child(sub {
    my $parent = shift;

    local $@;
    my $res = eval {
      local $SIG{__DIE__};
      $serialize->([undef, $job->(@args)]);
    };
    $res = $serialize->([$@]) if $@;

    $parent->write($res);
  });

  my $r = Mojo::IOLoop::Stream->new($child->read_handle);
  $self->ioloop->stream($r);

  my $buffer = '';
  $r->on( read  => sub { $buffer .= $_[1] } );
  $r->on( close => sub {
    my $res = do {
      local $@;
      eval { $self->deserialize->($buffer) } || [$@];
    };
    $self->emit( finish => @$res );
    return unless $child;
    $child->kill(9) unless $child->is_complete; 
    $child->wait;
  });
}

sub _child { Child->new($_[1], pipe => 1)->start }

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

