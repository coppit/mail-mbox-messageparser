package Mail::Mbox::MessageParser::Config;

use strict;

use vars qw( $VERSION %Config );

$VERSION = 0.01;

%Mail::Mbox::MessageParser::Config = (
  'programs' => {
    'bzip' => '/sw/bin/bzip2',
    'bzip2' => '/sw/bin/bzip2',
    'diff' => '/sw/bin/diff',
    'grep' => '/usr/bin/grep',
    'gzip' => '/sw/bin/gzip',
    'tzip' => undef,
  },

  'max_testchar_buffer_size' => 1048576,

  'read_chunk_size' => 20000,

  'from_pattern' => q/(?x)^
    (From\s
      # Skip names, months, days
      (?> [^:]+ )
      # Match time
      (?: :\d\d){1,2}
      # Match time zone (EST), hour shift (+0500), and-or year
      (?: \s+ (?: [A-Z]{2,3} | [+-]?\d{4} ) ){1,3}
      # smail compatibility
      (\sremote\sfrom\s.*)?
    )/,
);

1;

