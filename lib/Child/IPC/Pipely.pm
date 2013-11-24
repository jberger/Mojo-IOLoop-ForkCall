package Child::IPC::Pipely;

use strict;
use warnings;

use base 'Child::IPC::Pipe';

use IO::Pipely qw/pipely/;

sub shared_data {
  my ( $ain, $aout ) = pipely;
  my ( $bin, $bout ) = pipely;
  return [
    [ $ain, $aout ],
    [ $bin, $bout ],
  ];
}

1;

