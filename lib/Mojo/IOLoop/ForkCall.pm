package Mojo::IOLoop::ForkCall;

use Mojo::Base 'Mojo::EventEmitter';

our $VERSION = '0.01';
$VERSION = eval $VERSION;

use Mojo::IOLoop;
use Child;
use Storable ();
use Perl::OSType;

use Exporter 'import';

our @EXPORT_OK = qw/fork_call/;

use constant WINDOWS => ($ENV{FORKCALL_EMULATE_WINDOWS} // Perl::OSType::is_os_type('Windows'));

has 'ioloop' => sub { Mojo::IOLoop->singleton };
has 'serializer'   => sub { \&Storable::freeze };
has 'deserializer' => sub { \&Storable::thaw   };
has 'via' => sub { WINDOWS ? 'server' : 'child_pipe' };

sub run {
  my $self = shift;
  my $method = $self->can('_run_via_' . $self->via) 
    or die 'Cannot run via ' . $self->via;

  my $job  = shift;
  my $args = shift;
  $self->once( finish => shift ) if @_;
  $self->$method($job, $args);
}

sub _run_via_child_pipe {
  my ($self, $job, $args) = @_;
  my $serializer = $self->serializer;

  my $child = $self->_child(sub {
    my $parent = shift;
    my $res = _evaluate_job($serializer, $job, $args);
    $parent->write($res);
  });

  my $r = Mojo::IOLoop::Stream->new($child->read_handle);
  $self->ioloop->stream($r);

  my $buffer = '';
  $r->on( read  => sub { $buffer .= $_[1] } );
  $r->on( close => sub {
    $self->_emit_result($buffer);
    return unless $child;
    $child->kill(9) unless $child->is_complete; 
    $child->wait;
  });
}

sub _child { Child->new($_[1], pipe => 1)->start }

sub _run_via_server {
  my ($self, $job, $args) = @_;
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
        $self->_emit_result($buffer);
        # kill 9, $pid if WINDOWS; 
        waitpid $pid, 0; 
        $ioloop->remove($id);
      });
    });
  } else {
    # child
    my $res = _evaluate_job($serializer, $job, $args);
    $ioloop->client(%bind, sub {
      my ($loop, $err, $stream) = @_;
      $stream->on( close => sub { exit(0) } );
      $stream->on( drain => sub { shift->close } );
      $stream->write($res);
    });
  }
}

sub _emit_result {
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
  my ($serializer, $job, $args) = @_;
  local $@;
  my $res = eval {
    local $SIG{__DIE__};
    $serializer->([undef, $job->(@$args)]);
  };
  $res = $serializer->([$@]) if $@;
  return $res;
}

sub fork_call (&@) {
  my $cb = pop;
  my ($job, @args) = @_;
  my $fc = __PACKAGE__->new;
  $fc->on( finish => sub {
    shift;
    local $@ = shift;
    $cb->(@_);
  });
  $fc->run($job, @args);
}

1;

