package TestMojoApp;

use Mojolicious::Lite;

plugin 'Mojolicious::Plugin::ForkCall';

get '/slow' => sub {
  my $c = shift;
  my $len = $c->param('len') // die 'No sleep length given';
  $c->fork_call(sub {
    my $len = shift;
    die "$len is not a valid sleep length!" unless $len =~ /^\d+$/;
    sleep $len;
    return $len;
  }, [$len], sub {
    my ($c, $len) = @_;
    die "$len is too small!" unless $len >= 5;
    $c->render(json => {len => $len});
  });
};

package main;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('TestMojoApp');
$t->get_ok('/slow?len=5')->status_is(200)->json_is({len => 5});
$t->get_ok('/slow?len=1')->status_isnt(200);
$t->get_ok('/slow?len=asdf')->status_isnt(200);
$t->get_ok('/slow')->status_isnt(200);

done_testing;

