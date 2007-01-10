package Mail::Mbox::MessageParser::MetaInfo;

no strict;

@ISA = qw( Exporter );

use strict;
use Carp;

use Mail::Mbox::MessageParser;

use vars qw( $VERSION $DEBUG );
use vars qw( $CACHE %CACHE_OPTIONS $UPDATING_CACHE );

$VERSION = sprintf "%d.%02d%02d", q/0.1.1/ =~ /(\d+)/g;

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

# The class-wide cache, which will be read and written when necessary. i.e.
# read when an folder reader object is created which uses caching, and
# written when a different cache is specified, or when the program exits, 
$CACHE = {};

%CACHE_OPTIONS = ();

$UPDATING_CACHE = 0;

#-------------------------------------------------------------------------------

sub _LOAD_STORABLE
{
  if (eval 'require Storable;')
  {
    import Storable;
    return 1;
  }
  else
  {
    return 0;
  }
}

#-------------------------------------------------------------------------------

sub SETUP_CACHE
{
  my $cache_options = shift;

  carp "Need file_name option" unless defined $cache_options->{'file_name'};

  return "Can not load " . __PACKAGE__ . ": Storable is not installed.\n"
    unless _LOAD_STORABLE();
  
  # Load Storable if we need to
  # See if the client is setting up a different cache
  if (exists $CACHE_OPTIONS{'file_name'} &&
    $cache_options->{'file_name'} ne $CACHE_OPTIONS{'file_name'})
  {
    dprint "New cache file specified--writing old cache if necessary.";
    WRITE_CACHE();
    $CACHE = {};
  }

  %CACHE_OPTIONS = %$cache_options;

  _READ_CACHE();

  return 'ok';
}

#-------------------------------------------------------------------------------

sub CLEAR_CACHE
{
  unlink $CACHE_OPTIONS{'file_name'}
    if defined $CACHE_OPTIONS{'file_name'} && -f $CACHE_OPTIONS{'file_name'};

  $CACHE = {};
  $UPDATING_CACHE = 1;
}

#-------------------------------------------------------------------------------

sub INITIALIZE_ENTRY
{
  my $file_name = shift;

  my @stat = stat $file_name;

  return 0 unless @stat;

  my $size = $stat[7];
  my $time_stamp = $stat[9];


  if (exists $CACHE->{$file_name} &&
      (defined $CACHE->{$file_name}{'size'} &&
       defined $CACHE->{$file_name}{'time_stamp'} &&
       $CACHE->{$file_name}{'size'} == $size &&
       $CACHE->{$file_name}{'time_stamp'} == $time_stamp))
  {
    dprint "Cache is valid";

    # TODO: For now, if we re-initialize, we start over. Fix this so that we
    # can use partial cache information.
    if ($UPDATING_CACHE)
    {
      dprint "Resetting cache entry for \"$file_name\"\n";

      # Reset the cache entry for this file
      $CACHE->{$file_name}{'size'} = $size;
      $CACHE->{$file_name}{'time_stamp'} = $time_stamp;
      $CACHE->{$file_name}{'emails'} = [];
      $CACHE->{$file_name}{'modified'} = 0;
    }
  }
  else
  {
    if (exists $CACHE->{$file_name})
    {
      dprint "Size or time stamp has changed for file \"" .
        $file_name . "\". Invalidating cache entry";
    }
    else
    {
      dprint "Cache is invalid: \"$file_name\" has not yet been parsed";
    }

    $CACHE->{$file_name}{'size'} = $size;
    $CACHE->{$file_name}{'time_stamp'} = $time_stamp;
    $CACHE->{$file_name}{'emails'} = [];
    $CACHE->{$file_name}{'modified'} = 0;

    $UPDATING_CACHE = 1;
  }
}

#-------------------------------------------------------------------------------

sub ENTRY_STILL_VALID
{
  my $file_name = shift;

  return 0 unless exists $CACHE->{$file_name} &&
		defined $CACHE->{$file_name}{'size'} &&
		defined $CACHE->{$file_name}{'time_stamp'};

  my @stat = stat $file_name;

  return 0 unless @stat;

  my $size = $stat[7];
  my $time_stamp = $stat[9];

  return ($CACHE->{$file_name}{'size'} == $size &&
		$CACHE->{$file_name}{'time_stamp'} == $time_stamp);
}

#-------------------------------------------------------------------------------

sub _READ_CACHE
{
  my $self = shift;

  return unless -f $CACHE_OPTIONS{'file_name'};

  dprint "Reading cache";

  # Unserialize using Storable
  local $@;

  eval { $CACHE = retrieve($CACHE_OPTIONS{'file_name'}) };

  if ($@)
  {
    $CACHE = {};
    dprint "Invalid cache detected, and will be ignored.";
    dprint "Message from Storable module: \"$@\"";
  }
}

#-------------------------------------------------------------------------------

sub WRITE_CACHE
{
  # In case this is called during cleanup following an error loading
  # Storable
  return unless defined $Storable::VERSION;

  return if $UPDATING_CACHE;

  # TODO: Make this cache separate files instead of one big file, to improve
  # performance.
  my $cache_modified = 0;

  foreach my $file_name (keys %$CACHE)
  {
    if ($CACHE->{$file_name}{'modified'})
    {
      $cache_modified = 1;
      $CACHE->{$file_name}{'modified'} = 0;
    }
  }

  unless ($cache_modified)
  {
    dprint "Cache not modified, so no writing is necessary";
    return;
  }

  dprint "Cache was modified, so writing is necessary";

  # The mail box cache may contain sensitive information, so protect it
  # from prying eyes.
  my $oldmask = umask(077);

  # Serialize using Storable
  store($CACHE, $CACHE_OPTIONS{'file_name'});

  umask($oldmask);

  $CACHE->{$CACHE_OPTIONS{'file_name'}}{'modified'} = 0;
}

#-------------------------------------------------------------------------------

# Write the cache when the program exits
sub END
{
  dprint "Exiting and writing cache if necessary"
    if defined(&dprint);

  WRITE_CACHE();
}

1;

__END__

# --------------------------------------------------------------------------

=head1 NAME

Mail::Mbox::MessageParser::MetaInfo - A cache for folder metadata

=head1 DESCRIPTION

This module implements a cache for meta-information for mbox folders. The
information includes such items such as the file position, the line number,
and the byte offset of the start of each email.

=head2 METHODS AND FUNCTIONS

=over 4

=item SETUP_CACHE(...)

  SETUP_CACHE( { 'file_name' => <cache file name> } );

  <cache file name> - the file name of the cache

Call this function once to set up the cache before creating any parsers. You
must provide the location to the cache file. There is no default value.

Returns an error string or 1 if there is no error.

=item CLEAR_CACHE();

Use this function to clear the cache and delete the cache file.  Normally you
should not need to clear the cache--the module will automatically update the
cache when the mailbox changes. Call this function after I<SETUP_CACHE>.


=item WRITE_CACHE();

Use this function to force the module to write the in-memory cache information
to the cache file. Normally you do not need to do this--the module will
automatically write the information when the program exits.


=item $ref = new( { 'file_name' => <mailbox file name>,
                    'file_handle' => <mailbox file handle>, });

    <file_name> - The full filename of the mailbox
    <file_handle> - An opened file handle for the mailbox

The constructor for the class takes two parameters. I<file_name> is the
filename of the mailbox. This will be used as the cache key, so it's important
that it fully defines the path to the mailbox. The I<file_handle> argument is
the opened file handle to the mailbox. Both arguments are required.

Returns a reference to a Mail::Mbox::MessageParser object, or a string
describing the error.


=head1 BUGS

No known bugs.

Contact david@coppit.org for bug reports and suggestions.


=head1 AUTHOR

David Coppit <david@coppit.org>.


=head1 LICENSE

This software is distributed under the terms of the GPL. See the file
"LICENSE" for more information.


=head1 HISTORY

This code was originally part of the grepmail distribution. See
http://grepmail.sf.net/ for previous versions of grepmail which included early
versions of this code.


=head1 SEE ALSO

Mail::Mbox::MessageParser

=cut
