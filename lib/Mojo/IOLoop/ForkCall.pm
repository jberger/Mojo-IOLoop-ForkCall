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
  my $class = shift;
  if (@_ == 1 and ref $_[0] eq 'CODE') {
    unshift @_, 'job';
  }
  return $class->SUPER::new(@_);
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
    my $res = $self->deserialize->($buffer);
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

