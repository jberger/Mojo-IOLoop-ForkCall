package Mojolicious::Plugin::ForkCall;

use strict;
use warnings;
use Mojo::IOLoop::ForkCall;

use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.001';

sub register {
  my ($self, $app) = @_;

  $app->helper(fork_call => sub {
    my $c = shift;
    unless (@_ > 1 and ref $_[-1] eq 'CODE') {
      die 'fork_call helper must be passed a callback';
    }

    my $cb = pop;
    my @args = @_;

    $c->delay(
      sub{
        Mojo::IOLoop::ForkCall->new
          ->catch(sub{ die $_[1] })
          ->run(@args, shift->begin);
      },
      sub {
        my ($delay, $err, @return) = @_;
        die $err if $err;
        $c->$cb(@return);
      }
    );
  });
}

=head1 NAME

Mojolicious::Plugin::ForkCall - run blocking code asynchronously in Mojolicious
applications by forking

=head1 SYNOPSIS

 use Mojolicious::Lite;
 plugin 'Mojolicious::Plugin::ForkCall';
 get '/slow' => sub {
   my $c = shift;
   $c->fork_call(sub {
     my @args = @_;
     return do_slow_stuff(@args);
   }, [@args], sub {
     my @return = @_;
     $c->render(json => \@return);
   });
 };

 package My::Mojo::App;
 use Mojo::Base 'Mojolicious';
 sub startup {
   my $app = shift;
   $app->plugin('Mojolicious::Plugin::ForkCall');
   ...routes...
 }
 package My::Mojo::Controller;
 use Mojo::Base 'Mojolicious::Controller';
 sub some_action {
   my $self = shift;
   $self->fork_call(sub {
     my @args = @_;
     return do_slow_stuff(@args);
   }, [@args], sub {
     my @return = @_;
     $self->render(json => \@return);
   });
 }

=head1 DESCRIPTION

L<Mojolicious::Plugin::ForkCall> adds a helper method C<fork_call> to your
L<Mojolicious> or L<Mojolicious::Lite> application to run code in a forked
process using L<Mojo::IOLoop::ForkCall>.

=head1 METHODS

This module adds the following helper method to your application:

=head2 fork_call

 $c->fork_call(sub {
   my @args = @_;
   # This code is run in a forked process
   return @return;
 },
 [$arg1, $arg2, $arg3], # Arguments passed to the above code
 sub {
   my @return = @_;
   # This code is run in the current process once the child exits
 });

 # Code here is run before the async code above

The C<fork_call> method takes up to 3 arguments: a required code reference to
be run in a forked child process, an optional array reference of arguments to
be passed to the child code, and an optional code reference to be run in the
parent as a callback. The callback is passed the return value of the child.

If an exception occurs in the child process or in the parent callback, an
exception will be rendered as normal. This means that the parent callback will
not be called if the child process encounters an exception.

=cut

1;
