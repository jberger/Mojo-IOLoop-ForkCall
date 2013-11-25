package Mojo::IOLoop::ForkCall;

use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01';
$VERSION = eval $VERSION;

use Mojo::IOLoop;
use Child;
use Storable ();

use Exporter 'import';

our @EXPORT_OK = qw/fork_call/;

has 'ioloop'       => sub { Mojo::IOLoop->singleton };
has 'serializer'   => sub { \&Storable::freeze };
has 'deserializer' => sub { \&Storable::thaw   };
has 'weaken'       => 0;

sub run {
  my ($self, $job) = (shift, shift);
  my $args = shift if @_ and ref $_[0] eq 'ARRAY';
  $self->once( finish => shift ) if @_;

  my $serializer = $self->serializer;

  my $child = $self->_child(sub {
    my $parent = shift;
    local $@;
    my $res = eval {
      local $SIG{__DIE__};
      $serializer->([undef, $job->(@$args)]);
    };
    $res = $serializer->([$@]) if $@;
    $parent->write($res);
  });

  my $stream = Mojo::IOLoop::Stream->new($child->read_handle);
  $self->ioloop->stream($stream);

  my $buffer = '';
  $stream->on( read  => sub { $buffer .= $_[1] } );
  if ($self->weaken) {
    require Scalar::Util;
    Scalar::Util::weaken($self);
  }
  $stream->on( close => sub {
    my $res = do {
      local $@;
      eval { $self->deserializer->($buffer) } || [$@];
    };
    $self->emit( finish => @$res );
    return unless $child;
    # $child->kill(9) unless $child->is_complete; 
    $child->wait;
  });
}

sub _child { Child->new($_[1], pipely => 1)->start }

## functions

sub fork_call (&@) {
  my $job = shift;
  my $cb  = pop;
  my $fc = __PACKAGE__->new;
  $fc->on( finish => sub {
    shift;
    local $@ = shift;
    $cb->(@_);
  });
  $fc->run($job, \@_);
}

1;

