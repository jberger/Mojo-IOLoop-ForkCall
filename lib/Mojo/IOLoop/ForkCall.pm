package Mojo::IOLoop::ForkCall;

use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01';
$VERSION = eval $VERSION;

use Mojo::IOLoop;
use Child;
use Storable ();

use Exporter 'import';

our @EXPORT_OK = qw/fork_call/;

use constant WINDOWS => ($ENV{FORKCALL_EMULATE_WINDOWS} // $^O eq 'MSWIN32');

has 'ioloop' => sub { Mojo::IOLoop->singleton };
has 'job';
has 'serializer'   => sub { \&Storable::freeze };
has 'deserializer' => sub { \&Storable::thaw   };
has 'via' => sub { WINDOWS ? 'server' : 'child_pipe' };

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

# sub start {
#   my $self = shift;
#   $self->run(@_);
#   $self->ioloop->start unless $self->ioloop->is_running;
# }

sub run {
  my $self = shift;
  my $method = $self->can('run_via_' . $self->via) 
    or die 'Cannot run via ' . $self->via;
  $self->$method(@_);
}

sub run_via_child_pipe {
  my ($self, @args) = @_;
  my $job = $self->job;
  my $serializer = $self->serializer;

  my $child = $self->_child(sub {
    my $parent = shift;
    my $res = _evaluate_job($serializer, $job, @args);
    $parent->write($res);
  });

  my $r = Mojo::IOLoop::Stream->new($child->read_handle);
  $self->ioloop->stream($r);

  my $buffer = '';
  $r->on( read  => sub { $buffer .= $_[1] } );
  $r->on( close => sub {
    $self->emit_result($buffer);
    return unless $child;
    $child->kill(9) unless $child->is_complete; 
    $child->wait;
  });
}

sub _child { Child->new($_[1], pipe => 1)->start }

sub run_via_server {
  my ($self, @args) = @_;
  my $job = $self->job;
  my $serializer = $self->serializer;
  my $ioloop = $self->ioloop;

  my %bind = (
    address => '127.0.0.1',
    port    => $ioloop->generate_port,
  );
  my $pid = fork;
  if ($pid) {
    # parent
    $ioloop->server(%bind, sub {
      my ($ioloop, $stream, $id) = @_;
      my $buffer = '';
      $stream->on( read  => sub { $buffer .= $_[1] } );
      $stream->on( close => sub {
        $self->emit_result($buffer);
        # kill 9, $pid if WINDOWS; 
        waitpid $pid, 0; 
        $ioloop->remove($id);
      });
    });
  } else {
    # child
    my $res = _evaluate_job($serializer, $job, @args);
    $ioloop->client(%bind, sub {
      my ($loop, $err, $stream) = @_;
      $stream->on( close => sub { exit(0) } );
      $stream->on( drain => sub { shift->close } );
      $stream->write($res);
    });
  }
}

sub emit_result {
  my ($self, $buffer) = @_;
  my $res = do {
    local $@;
    eval { $self->deserializer->($buffer) } || [$@];
  };
  $self->emit( finish => @$res );
}

## functions

# since this is called on child, avoid closing over self
sub _evaluate_job {
  my ($serializer, $job, @args) = @_;
  local $@;
  my $res = eval {
    local $SIG{__DIE__};
    $serializer->([undef, $job->(@args)]);
  };
  $res = $serializer->([$@]) if $@;
  return $res;
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
  $fc->run;
}

1;

