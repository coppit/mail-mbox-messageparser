package Mail::Mbox::MessageParser::Cache;

no strict;

@ISA = qw( Exporter Mail::Mbox::MessageParser );

use strict;
use Carp;
use Mail::Mbox::MessageParser;

use vars qw( $VERSION $DEBUG $CACHE %CACHE_OPTIONS $UPDATING_CACHE
  $CACHE_MODIFIED );

$VERSION = '1.01';

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

# The class-wide cache, which will be read and written when necessary. i.e.
# read when an folder reader object is created which uses caching, and
# written when a different cache is specified, or when the program exits, 
$CACHE = undef;

%CACHE_OPTIONS = ();

$UPDATING_CACHE = 0;

$CACHE_MODIFIED = 0;

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
  my $options = shift;

  return "Can not load " . __PACKAGE__ . ": Storable is not installed.\n"
    unless _LOAD_STORABLE();
  
  # Load Storable if we need to
  # See if the client is setting up a different cache
  if (exists $CACHE_OPTIONS{'file_name'} &&
    $options->{'file_name'} ne $CACHE_OPTIONS{'file_name'})
  {
    dprint "New cache file specified--writing old cache if necessary.";
    WRITE_CACHE() if $CACHE_MODIFIED;
    undef $CACHE;
  }

  %CACHE_OPTIONS = %$options;

  _READ_CACHE() if -f $CACHE_OPTIONS{'file_name'};

  $CACHE_MODIFIED = 0;

  return 'ok';
}

#-------------------------------------------------------------------------------

sub CLEAR_CACHE
{
  unlink $CACHE_OPTIONS{'file_name'}
    if defined $CACHE_OPTIONS{'file_name'} && -f $CACHE_OPTIONS{'file_name'};

  $CACHE = undef;
  $CACHE_MODIFIED = 0;
  $UPDATING_CACHE = 1;
}

#-------------------------------------------------------------------------------

sub _READ_CACHE
{
  my $self = shift;

  dprint "Reading cache";

  # Unserialize using Storable
  $CACHE = retrieve($CACHE_OPTIONS{'file_name'});
}

#-------------------------------------------------------------------------------

sub WRITE_CACHE
{
  # In case this is called during cleanup following an error loading
  # Storable
  return unless defined $Storable::VERSION;

  dprint "Writing cache.";

  # The mail box cache may contain sensitive information, so protect it
  # from prying eyes.
  my $oldmask = umask(077);

  # Serialize using Storable
  store($CACHE, $CACHE_OPTIONS{'file_name'});

  umask($oldmask);

  $CACHE_MODIFIED = 0;
}

#-------------------------------------------------------------------------------

# Write the cache when the program exits
sub END
{
  dprint "Exiting and writing cache if necessary"
    if defined(&dprint);

  WRITE_CACHE() if $CACHE_MODIFIED;
}

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $options) = @_;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  carp "Call SETUP_CACHE() before calling new()"
    unless defined $CACHE_OPTIONS{'file_name'};

  # We need to write the cache if the user fully parsed a previous file before
  # trying to parse this one. Theoretically we could track the modification of
  # each cache entry separately, but a single global modified bit should work
  # for 99% of the cases.
  WRITE_CACHE() if $CACHE_MODIFIED && !$UPDATING_CACHE;

  carp "Need file_name option" unless defined $options->{'file_name'};
  carp "Need file_handle option" unless defined $options->{'file_handle'};

  $self->{'file_handle'} = undef;
  $self->{'file_handle'} = $options->{'file_handle'}
    if exists $options->{'file_handle'};

  # The buffer information. (Used when caching is not enabled)
  $self->{'READ_BUFFER'} = '';

  $self->{'end_of_file'} = 0;

  # The line number of the last read email.
  $self->{'email_line_number'} = 0;
  # The offset of the last read email.
  $self->{'email_offset'} = 0;
  # The length of the last read email.
  $self->{'email_length'} = 0;

  $self->{'email_number'} = 0;

  # We need the file name as a key to the cache
  $self->{'file_name'} = $options->{'file_name'};

  $self->_print_debug_information();

  $self->_validate_and_initialize_cache_entry();

  return $self;
}

#-------------------------------------------------------------------------------

sub reset
{
  my $self = shift;

  seek $self->{'file_handle'}, length($self->{'prologue'}), 0;

  $self->{'READ_BUFFER'} = '';

  $self->{'end_of_file'} = 0;

  $self->{'email_line_number'} = 0;
  $self->{'email_offset'} = 0;
  $self->{'email_length'} = 0;
  $self->{'email_number'} = 0;

  # If we're in the middle of parsing this file, we need to reset the cache
  if ($UPDATING_CACHE)
  {
    dprint "Resetting cache\n";

    my @stat = stat $self->{'file_name'};

    my $size = $stat[7];
    my $time_stamp = $stat[9];

    # Reset the cache entry for this file
    delete $CACHE->{$self->{'file_name'}};
    $CACHE->{$self->{'file_name'}}{'size'} = $size;
    $CACHE->{$self->{'file_name'}}{'time_stamp'} = $time_stamp;
    $CACHE->{$self->{'file_name'}}{'lengths'} = [];

    $CACHE_MODIFIED = 0;
  }
}

#-------------------------------------------------------------------------------

sub _read_prologue
{
  my $self = shift;

  my $prologue_length = $CACHE->{$self->{'file_name'}}{'offsets'}[0];

  {
    my $bytes_read = 0;
    do {
      $bytes_read += read($self->{'file_handle'}, $self->{'prologue'},
        $prologue_length-$bytes_read, $bytes_read);
    } while ($bytes_read != $prologue_length);
  }
}

#-------------------------------------------------------------------------------

sub _print_debug_information
{
  return unless $DEBUG;

  my $self = shift;

  $self->SUPER::_print_debug_information();

  dprint "Valid cache entry exists: " .
    ($#{ $CACHE->{$self->{'file_name'}}{'lengths'} } != -1 ? "Yes" : "No");
}

#-------------------------------------------------------------------------------

sub _validate_and_initialize_cache_entry
{
  my $self = shift;

  $CACHE_MODIFIED = 0;

  my @stat = stat $self->{'file_name'};

  my $size = $stat[7];
  my $time_stamp = $stat[9];

  if (exists $CACHE->{$self->{'file_name'}} &&
      ($CACHE->{$self->{'file_name'}}{'size'} != $size ||
       $CACHE->{$self->{'file_name'}}{'time_stamp'} != $time_stamp))
  {
    dprint "Size or time stamp has changed for file " .
      $self->{'file_name'} . ". Invalidating cache entry";

    delete $CACHE->{$self->{'file_name'}};
  }

  if (exists $CACHE->{$self->{'file_name'}})
  {
    dprint "Cache is valid";

    $UPDATING_CACHE = 0;
  }
  else
  {
    dprint "Cache is invalid: \"$self->{'file_name'}\" has not been parsed";

    $CACHE->{$self->{'file_name'}}{'size'} = $size;
    $CACHE->{$self->{'file_name'}}{'time_stamp'} = $time_stamp;
    $CACHE->{$self->{'file_name'}}{'lengths'} = [];

    $UPDATING_CACHE = 1;
  }
}

#-------------------------------------------------------------------------------

sub read_next_email
{
  my $self = shift;

  $self->{'email_line_number'} =
    $CACHE->{$self->{'file_name'}}{'line_numbers'}[$self->{'email_number'}];
  $self->{'email_offset'} =
    $CACHE->{$self->{'file_name'}}{'offsets'}[$self->{'email_number'}];
  $self->{'email_length'} = 
    $CACHE->{$self->{'file_name'}}{'lengths'}[$self->{'email_number'}];

  $self->{'READ_BUFFER'} = '';

  {
    my $bytes_read = 0;
    do {
      $bytes_read += read($self->{'file_handle'}, $self->{'READ_BUFFER'}, $self->{'email_length'}-$bytes_read, $bytes_read);
    } while ($bytes_read != $self->{'email_length'});
  }

  if ($self->{'email_number'} ==
    $#{ $CACHE->{$self->{'file_name'}}{'lengths'} })
  {
    $self->{'end_of_file'} = 1;
    $UPDATING_CACHE = 0;
  }

  $self->{'email_number'}++;

  return \$self->{'READ_BUFFER'};
}

1;

__END__

# --------------------------------------------------------------------------

=head1 NAME

Mail::Mbox::MessageParser::Cache - A cache-based mbox folder reader

=head1 SYNOPSIS

  #!/usr/bin/perl

  use Mail::Mbox::MessageParser::Cache;

  # Set up cache
  Mail::Mbox::MessageParser::Cache::SETUP_CACHE(
    { 'file_name' => '/tmp/cache' } );

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  my $folder_reader =
    new Mail::Mbox::MessageParser::Cache( {
      'file_name' => $filename,
      'file_handle' => $filehandle,
    } );

  die $folder_reader unless ref $folder_reader;
  
  die "No cached information"
    if $Mail::Mbox::MessageParser::Cache::UPDATING_CACHE;

  # Any newlines or such before the start of the first email
  my $prologue = $folder_reader->prologue;
  print $prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file());
  {
    my $email = $folder_reader->read_next_email();
    print $email;
  }

=head1 DESCRIPTION

This module implements a cached-based mbox folder reader. It can only be used
when cache information already exists. Users are encouraged to use
Mail::Mbox::MessageParser instead. The base MessageParser module will
automatically fall back to another reader implementation if cached information
is not available, and will fill the cache after parsing is done.

=head2 METHODS AND FUNCTIONS

The following methods and functions are specific to the
Mail::Mbox::MessageParser::Cache package. For additional inherited ones, see
the Mail::Mbox::MessageParser documentation.

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
                    'file_handle' => <mailbox file handle> });

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
