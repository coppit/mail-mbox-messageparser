package Mail::Mbox::MessageParser;

no strict;

@ISA = qw(Exporter);

use strict;
use Carp;
use FileHandle;

sub dprint;

use Mail::Mbox::MessageParser::Perl;
use Mail::Mbox::MessageParser::Grep;
use Mail::Mbox::MessageParser::Cache;

use vars qw( $VERSION $DEBUG $UPDATING_CACHE %PROGRAMS );

$VERSION = '1.10';
$DEBUG = 0;

$UPDATING_CACHE = 0;

%PROGRAMS = (
 'grep' => '/usr/cs/contrib/bin/grep',
 'tzip' => undef,
 'gzip' => '/usr/cs/contrib/bin/gzip',
 'compress' => '/usr/cs/contrib/bin/gzip',
 'bzip' => undef,
 'bzip2' => undef,
);

#-------------------------------------------------------------------------------

# Outputs debug messages if $DEBUG is true. Be sure to return 1 so code like
# 'dprint "blah\n" and exit' works.

sub dprint
{
  return 1 unless $DEBUG;

  my $message = join '',@_;

  foreach my $line (split /\n/, $message)
  {
    warn "DEBUG (" . __PACKAGE__ . "): $line\n";
  }

  return 1;
}

#-------------------------------------------------------------------------------

sub SETUP_CACHE
{
  Mail::Mbox::MessageParser::Cache::SETUP_CACHE(@_);
}

#-------------------------------------------------------------------------------

sub CLEAR_CACHE
{
  Mail::Mbox::MessageParser::Cache::CLEAR_CACHE(@_);
}

#-------------------------------------------------------------------------------

sub WRITE_CACHE
{
  Mail::Mbox::MessageParser::Cache::WRITE_CACHE(@_);
}

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $options, $cache_options) = @_;

  my $class = ref($proto) || $proto;

  my $self = undef;

  $UPDATING_CACHE = 0;

  carp "You must provide either a file name or a file handle"
    unless defined $options->{'file_name'} || defined $options->{'file_handle'};

  # Can't use grep or cache unless there is a filename
  unless (defined $options->{'file_name'})
  {
    $options->{'enable_cache'} = 0;
    $options->{'enable_grep'} = 0;
  }

  my ($file_type, $need_to_close_filehandle, $error);

  ($options->{'file_handle'}, $file_type, $need_to_close_filehandle, $error) =
    _PREPARE_FILE_HANDLE($options->{'file_name'}, $options->{'file_handle'});

  return $error unless !defined $error ||
    ($error eq 'Not a mailbox' && $options->{'force_processing'});

  # Grep implementation doesn't support compression right now
  $options->{'enable_grep'} = 0 if _IS_COMPRESSED_TYPE($file_type);

  if (defined $options->{'enable_cache'} && $options->{'enable_cache'})
  {
    $self = new Mail::Mbox::MessageParser::Cache($options, $cache_options);

    unless (ref $self)
    {
      warn "Couldn't instantiate Mail::Mbox::MessageParser::Cache: $self";
      $self = undef;
    }

    if ($Mail::Mbox::MessageParser::Cache::UPDATING_CACHE)
    {
      $UPDATING_CACHE = 1;
      $self = undef;
    }
  }

  if (!defined $self &&
    defined $options->{'enable_grep'} && $options->{'enable_grep'})
  {
    $self = new Mail::Mbox::MessageParser::Grep($options);

    unless (ref $self)
    {
      warn "Couldn't instantiate Mail::Mbox::MessageParser::Grep: $self";
      $self = undef;
    }
  }

  if (!defined $self)
  {
    $self = new Mail::Mbox::MessageParser::Perl($options);

    unless (ref $self)
    {
      die "Couldn't instantiate Mail::Mbox::MessageParser::Perl: $self";
    }
  }

  $DEBUG = $options->{'debug'}
    if defined $options->{'debug'};

  $self->_print_debug_information();

  $self->_read_prologue();

  $self->{'need_to_close_filehandle'} = $need_to_close_filehandle;

  return $self;
}

#-------------------------------------------------------------------------------

sub DESTROY
{
  my $self = shift;

  $self->{'file_handle'}->close() if $self->{'need_to_close_filehandle'};
}

#-------------------------------------------------------------------------------

# Returns a file handle to the decompressed mailbox.
sub _PREPARE_FILE_HANDLE
{
  my $file_name = shift;
  my $file_handle = shift;

  if (defined $file_handle)
  {
    my $file_type = _GET_FILE_TYPE($file_handle);

    # Do decompression if we need to
    if (_IS_COMPRESSED_TYPE($file_type))
    {
      my ($decompressed_file_handle,$error) =
        _DO_DECOMPRESSION($file_handle, $file_type);

      return ($file_handle,$file_type,0,$error)
        unless defined $decompressed_file_handle;

      return ($decompressed_file_handle,$file_type,0,"Not a mailbox")
        if _GET_FILE_TYPE($decompressed_file_handle) ne 'mailbox';

      return ($decompressed_file_handle,$file_type,0,undef);
    }
    else
    {
      return ($file_handle,$file_type,0,"No data on filehandle")
        unless _DATA_ON_FILE_HANDLE($file_handle);

      return ($file_handle,$file_type,0,"Not a mailbox")
        if $file_type ne 'mailbox';

      return ($file_handle,$file_type,0,undef);
    }
  }
  else
  {
    my $file_type = _GET_FILE_TYPE($file_name);

    my ($opened_file_handle,$error) =
      _OPEN_FILE_HANDLE($file_name, $file_type);

    return ($file_handle,$file_type,0,$error)
      unless defined $opened_file_handle;

    if (_IS_COMPRESSED_TYPE($file_type))
    {
      return ($opened_file_handle,$file_type,1,"Not a mailbox")
        if _GET_FILE_TYPE($opened_file_handle) ne 'mailbox';

      return ($opened_file_handle,$file_type,1,undef);
    }
    else
    {
      return ($opened_file_handle,$file_type,1,"Not a mailbox")
        if $file_type ne 'mailbox';

      return ($opened_file_handle,$file_type,1,undef);
    }
  }
}

#-------------------------------------------------------------------------------

# This function does not analyze the file to determine if it is valid. It only
# opens it using a suitable decompresson if necessary.
sub _OPEN_FILE_HANDLE
{
  my $file_name = shift;
  my $file_type = shift;

  # Non-compressed file
  unless (_IS_COMPRESSED_TYPE($file_type))
  {
    my $file_handle = new FileHandle($file_name);
    return (undef,"Can't open $file_name: $!") unless defined $file_handle;
    return ($file_handle,undef);
  }

  return (undef,"Can't decompress $file_name--no decompressor available")
    unless defined $PROGRAMS{$file_type};

  # It must be a known compressed file type
  my $filter_command = "$PROGRAMS{$file_type} -cd '$file_name' |";

  dprint "Calling \"$filter_command\" to decompress file.";

  use vars qw(*OLDSTDERR);
  open OLDSTDERR,">&STDERR" or die "Can't save STDERR: $!\n";
  open STDERR,">/dev/null"
    or die "Can't redirect STDERR to /dev/null: $!\n";

  my $file_handle = new FileHandle($filter_command);

  open STDERR,">&OLDSTDERR" or die "Can't restore STDERR: $!\n";

  return (undef,"Can't execute \"$filter_command\" for file \"$file_name\": $!")
    unless defined $file_handle;

  unless (_DATA_ON_FILE_HANDLE($file_handle))
  {
    $file_handle->close();
    return (undef,"Can't execute \"$filter_command\" for file \"$file_name\"");
  }

  return ($file_handle, undef);
}

#-------------------------------------------------------------------------------

# Returns: unknown, unknown binary, mailbox, non-mailbox ascii, tzip, bzip,
# bzip2, gzip, compress
sub _GET_FILE_TYPE
{
  my $file_name_or_handle = shift;

  # Open the file if we need to
  my $file_handle;
  my $need_to_close_filehandle = 0;  

  if (ref \$file_name_or_handle eq 'SCALAR')
  {
    $file_handle = new FileHandle($file_name_or_handle);
    return 'unknown' unless defined $file_handle;

    $need_to_close_filehandle = 1;
  }
  else
  {
    $file_handle = $file_name_or_handle;
  }

  
  # Read test characters
  my $testChars;

  binmode $file_handle;

  my $readResult = read($file_handle,$testChars,2000);

  $file_handle->close() if $need_to_close_filehandle;

  return 'unknown' unless defined $readResult && $readResult != 0;


  _PUT_BACK_STRING($file_handle,$testChars) unless $need_to_close_filehandle;

  # Do -B on the data stream
  my $isBinary = 0;
  {
    my $data_length = CORE::length($testChars);
    my $bin_length = $testChars =~ tr/[\t\n\x20-\x7e]//c;
    my $non_bin_length = $data_length - $bin_length;
    $isBinary = ($non_bin_length / $data_length) > .70 ? 0 : 1;
  }

  unless ($isBinary)
  {
    return 'mailbox' if _IS_MAILBOX($testChars);
    return 'non-mailbox ascii';
  }

  # See "magic" on unix systems for details on how to identify file types
  return 'tzip' if substr($testChars, 0, 2) eq 'TZ';
  return 'bzip2' if substr($testChars, 0, 3) eq 'BZh';
  return 'bzip' if substr($testChars, 0, 2) eq 'BZ';
#  return 'zip' if substr($testChars, 0, 2) eq 'PK' &&
#    ord(substr($testChars,3,1)) == 0003 && ord(substr($testChars,4,1)) == 0004;
  return 'gzip' if
    ord(substr($testChars,0,1)) == 0037 && ord(substr($testChars,1,1)) == 0213;
  return 'compress' if
    ord(substr($testChars,0,1)) == 0037 && ord(substr($testChars,1,1)) == 0235;

  return 'unknown binary';
}

#-------------------------------------------------------------------------------

sub _IS_COMPRESSED_TYPE
{
  my $file_type = shift;
  
  local $" = '|';

  my @types = keys %PROGRAMS;
  my $file_type_pattern = "(@types)";

  return $file_type =~ /^$file_type_pattern$/;
}

#-------------------------------------------------------------------------------

sub _DO_DECOMPRESSION
{
  my $file_handle = shift;
  my $file_type = shift;

  return (undef,"Can't decompress file handle--no decompressor available")
    unless defined $PROGRAMS{$file_type};

  my $filter_command = "$PROGRAMS{$file_type} -cd";

  # Implicit fork
  my $decompressed_file_handle = new FileHandle;
  my $pid = $decompressed_file_handle->open('-|');

  unless (defined($pid))
  {
    $file_handle->close();
    die 'Can\'t fork to decompress file handle';
  }

  # In child. Write to the parent, giving it all the data to decompress.
  # We have to do it this way because other methods (e.g. open2) require us
  # to feed the filter as we use the filtered data. This method allows us to
  # keep the remainder of the code the same for both compressed and
  # uncompressed input.
  unless ($pid)
  {
    open(FRONT_OF_PIPE, "|$filter_command 2>/dev/null")
      or return (undef,"Can't execute \"$filter_command\" on file handle: $!");

    print FRONT_OF_PIPE <$file_handle>;

    $file_handle->close()
      or return (undef,"Can't execute \"$filter_command\" on file handle: $!");

    # We intentionally don't check for error here. This is because the
    # parent may have aborted, in which case we let it take care of
    # error messages. (e.g. Non-mailbox standard input.)
    close FRONT_OF_PIPE;

    exit;
  }

  # In parent
  return ($decompressed_file_handle,undef);
}

#-------------------------------------------------------------------------------

sub _OPEN_DECOMPRESSION_FILE_HANDLE
{
  my $command = shift;

}

#-------------------------------------------------------------------------------

# Checks to see if there is data on a filehandle, without reading that data.

sub _DATA_ON_FILE_HANDLE
{
  my $file_handle = shift;

  my $buffer = <$file_handle>;

  return 0 unless defined $buffer;

  _PUT_BACK_STRING($file_handle,$buffer);

  return $buffer ? 1 : 0;
}

#-------------------------------------------------------------------------------

# Puts a string back on a file handle

sub _PUT_BACK_STRING
{
  my $file_handle = shift;
  my $string = shift;

  for (my $char_position=CORE::length($string)-1;$char_position >=0; $char_position--)
  {
    $file_handle->ungetc(ord(substr($string,$char_position,1)));
  }
}

#-------------------------------------------------------------------------------

# Detects whether an ASCII file is a mailbox, based on whether it has
# a line whose prefix is 'From' or 'X-From-Line:' or 'X-Draft-From:',
# and another line whose prefix is 'Received ', 'Date:', 'Subject:',
# 'X-Status:', 'Status:', or 'To:'.

sub _IS_MAILBOX
{
  my $test_characters = shift;

  # X-From-Line is used by Gnus, and From is used by normal Unix
  # format. Newer versions of Gnus use X-Draft-From
#  if ($buffer =~ /^(X-Draft-From:|X-From-Line:|From)\s/im &&
#      $buffer =~ /^(Date|Subject|X-Status|Status|To):\s/im)
  if ($test_characters =~ /^(X-Draft-From:|X-From-Line:|From:?)\s/im &&
      $test_characters =~ /^Received:.*\bfrom\b.*\bby\b.*for\b/sm)
  {
    return 1;
  }
  else
  {
    return 0;
  }
}

#-------------------------------------------------------------------------------

sub reset
{
  die "Derived class must provide an implementation";
}

#-------------------------------------------------------------------------------

sub prologue
{
  my $self = shift;

  return $self->{'prologue'};
}

#-------------------------------------------------------------------------------

sub _print_debug_information
{
  return unless $DEBUG;

  my $self = shift;

  dprint "Version: $VERSION";
  dprint "Email file: $self->{'file_name'}";
}

#-------------------------------------------------------------------------------

# Returns true if the file handle has been fully read
sub end_of_file
{
  my $self = shift;

  return $self->{'end_of_file'};
}

#-------------------------------------------------------------------------------

# The line number of the last email read
sub line_number
{
  my $self = shift;

  return $self->{'email_line_number'};
}

#-------------------------------------------------------------------------------

sub number
{
  my $self = shift;

  return $self->{'email_number'};
}

#-------------------------------------------------------------------------------

# The length of the last email read
sub length
{
  my $self = shift;

  return $self->{'email_length'};
}

#-------------------------------------------------------------------------------

# The offset of the last email read
sub offset
{
  my $self = shift;

  return $self->{'email_offset'};
}

#-------------------------------------------------------------------------------

sub _read_prologue
{
  die "Derived class must provide an implementation";
}

#-------------------------------------------------------------------------------

sub read_next_email
{
  my $self = shift;

  if ($UPDATING_CACHE)
  {
    dprint "Storing data into cache, length " . $self->{'email_length'};

    my $cache = $Mail::Mbox::MessageParser::Cache::CACHE;

    $cache->{$self->{'file_name'}}{'lengths'}[$self->{'email_number'}-1] =
      $self->{'email_length'};

    $cache->{$self->{'file_name'}}{'line_numbers'}[$self->{'email_number'}-1] =
      $self->{'email_line_number'};

    $cache->{$self->{'file_name'}}{'offsets'}[$self->{'email_number'}-1] =
      $self->{'email_offset'};

    $Mail::Mbox::MessageParser::Cache::CACHE_MODIFIED = 1;
  }

}

1;

__END__

# --------------------------------------------------------------------------

=head1 NAME

Mail::Mbox::MessageParser - A fast and simple mbox folder reader

=head1 SYNOPSIS

  #!/usr/bin/perl

  use Mail::Mbox::MessageParser;

  my $file_name = 'mail/saved-mail';
  my $file_handle = new FileHandle($file_name);

  # Set up cache. (Not necessary if enable_cache is false.)
  Mail::Mbox::MessageParser::SETUP_CACHE(
    { 'file_name' => '/tmp/cache' } );

  my $folder_reader =
    new Mail::Mbox::MessageParser( {
      'file_name' => $file_name,
      'file_handle' => $file_handle,
      'enable_cache' => 1,
      'enable_grep' => 1,
    } );

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

This module implements a fast but simple mbox folder reader. One of three
implementations (Cache, Grep, Perl) will be used depending on the wishes of the
user and the system configuration. The first implementation is a cached-based
one which stores email information about mailboxes on the file system.
Subsequent accesses will be faster because no analysis of the mailbox will be
needed. The second implementation is one based on GNU grep, and is
significantly faster than the Perl version for mailboxes which contain very
large (10MB) emails. The final implementation is a fast Perl-based one which
should always be applicable.

The Cache implementation is about 6 times faster than the standard Perl
implementation. The Grep implementation is about 4 times faster than the
standard Perl implementation. If you have GNU grep, it's best to enable both
the Cache and Grep implementations. If the cache information is available,
you'll get very fast speeds. Otherwise, you'll take about a 1/3 performance
hit when the Grep version is used instead.

The overriding requirement for this module is speed. If you wish more
sophisticated parsing, use Mail::MboxParser (which is based on this module) or
Mail::Box.


=head2 METHODS AND FUNCTIONS

=over 4

=item SETUP_CACHE(...)

  SETUP_CACHE( { 'file_name' => <cache file name> } );

  <cache file name> - the file name of the cache

Call this function once to set up the cache before creating any parsers. You
must provide the location to the cache file. There is no default value.

=item new(...)

  new( { 'file_name' => <mailbox file name>,
    'file_handle' => <mailbox file handle>,
    'enable_cache' => <1 or 0>,
    'enable_grep' => <1 or 0>,
    'force_processing' => <1 or 0>,
    'debug' => <1 or 0>,
  } );

  <mailbox file name> - the file name of the mailbox
  <mailbox file handle> - the already opened file handle for the mailbox
  <enable_cache> - true to attempt to use the cache implementation
  <enable_grep> - true to attempt to use the grep implementation
  <force_processing> - true to force processing of files that look invalid
  <debug> - true to print some debugging information to STDERR

The constructor takes either a file name or a file handle, or both. If the
file handle is not defined, Mail::Mbox::MessageParser will attempt to open the
file using the file name. You should always pass the file name if you have it, so
that the parser can cache the mailbox information.

This module will automatically decompress the mailbox as necessary. If a
filename is available but the file handle is undef, the module will call
either tzip, bzip2, or gzip to decompress the file in memory if the filename
ends with .tz, .bz2, or .gz, respectively. If the file handle is defined, it
will detect the type of compression and apply the correct decompression
program.

The Cache, Grep, or Perl implementation of the parser will be loaded,
whichever is most appropriate. For example, the first time you use caching,
there will be no cache. In this case, the grep implementation can be used
instead. The cache will be updated in memory as the grep implementation parses
the mailbox, and the cache will be written after the program exits. The file
name is optional, in which case I<enable_cache> and I<enable_grep> must both
be false.

Returns a reference to a Mail::Mbox::MessageParser object on success, and a
scalar desribing an error on failure. ("Not a mailbox", "Can't open <filename>: <system error>", "Can't execute <uncompress command> for file <filename>"


=item reset()

Reset the filehandle and all internal state. Note that this will not work with
filehandles which are streams. If there is enough demand, I may add the
ability to store the previously read stream data internally so that I<reset()>
will work correctly.


=item prologue()

Returns any newlines or other content at the start of the mailbox prior to the
first email.


=item end_of_file()

Returns true if the end of the file has been encountered.


=item line_number()

Returns the line number for the start of the last email read.


=item number()

Returns the number of the last email read. (i.e. The first email will have a
number of 1.)


=item length()

Returns the length of the last email read.


=item offset()

Returns the byte offset of the last email read.


=item read_next_email()

Returns a reference to a scalar holding the text of the next email in the
mailbox.

=back


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

Mail::MboxParser, Mail::Box

=cut
