package Mail::Mbox::MessageParser;

no strict;

@ISA = qw(Exporter);

use strict;
use warnings 'all';
no warnings 'redefine';

our $VERSION = '1.00';
our $DEBUG = 0;

our $UPDATING_CACHE = 0;

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
  if (eval 'require Mail::Mbox::MessageParser::Cache;')
  {
    Mail::Mbox::MessageParser::Cache::SETUP_CACHE(@_);
  }
  else
  {
    # We'll catch loading errors later in new()
  }
}

#-------------------------------------------------------------------------------

sub CLEAR_CACHE
{
  if (eval 'require Mail::Mbox::MessageParser::Cache;')
  {
    Mail::Mbox::MessageParser::Cache::CLEAR_CACHE(@_);
  }
  else
  {
    # We'll catch loading errors later in new()
  }
}

#-------------------------------------------------------------------------------

sub WRITE_CACHE
{
  if (eval 'require Mail::Mbox::MessageParser::Cache;')
  {
    Mail::Mbox::MessageParser::Cache::WRITE_CACHE(@_);
  }
  else
  {
    # We'll catch loading errors later in new()
  }
}

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $options, $cache_options) = @_;

  my $class = ref($proto) || $proto;

  my $self = undef;

  $UPDATING_CACHE = 0;

  if (defined $options->{'enable_cache'} && $options->{'enable_cache'})
  {
    if (eval 'require Mail::Mbox::MessageParser::Cache;')
    {
      $self = new Mail::Mbox::MessageParser::Cache($options, $cache_options);

      if ($Mail::Mbox::MessageParser::Cache::UPDATING_CACHE)
      {
        $UPDATING_CACHE = 1;
        $self = undef;
      }
    }
    else
    {
      dprint "Couldn't load Mail::Mbox::MessageParser::Cache: $@";
    }
  }

  if (!defined $self &&
    defined $options->{'enable_grep'} && $options->{'enable_grep'})
  {
    if (eval 'require Mail::Mbox::MessageParser::Grep;')
    {
      $self = new Mail::Mbox::MessageParser::Grep($options);
    }
    else
    {
      dprint "Couldn't load Mail::Mbox::MessageParser::Grep: $@";
    }
  }

  if (!defined $self)
  {
    if (eval 'require Mail::Mbox::MessageParser::Perl;')
    {
      $self = new Mail::Mbox::MessageParser::Perl($options);
    }
    else
    {
      die "Couldn't load Mail::Mbox::MessageParser::Perl: $@";
    }
  }

  $DEBUG = $options->{'debug'}
    if defined $options->{'debug'};

  $self->_print_debug_information();

  $self->_read_prologue();

  return $self;
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

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  # Set up cache. (Not necessary if enable_cache is false.)
  Mail::Mbox::MessageParser::SETUP_CACHE(
    { 'file_name' => '/tmp/cache' } );

  my $folder_reader =
    new Mail::Mbox::MessageParser( {
      'file_name' => $filename,
      'file_handle' => $filehandle,
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
    'debug' => <1 or 0>,
  } );

  <mailbox file name> - the file name of the mailbox
  <mailbox file handle> - the already opened file handle for the mailbox
  <enable_cache> - true to attempt to use the cache implementation
  <enable_grep> - true to attempt to use the grep implementation
  <debug> - true to print some debugging information to STDERR

This constructor will attempt to load the Cache, Grep, and Perl implementations
as necessary. For example, the first time you use caching, there will be no
cache. In this case, the grep implementation can be used instead. The cache
will be updated in memory as the grep implementation parses the mailbox, and
the cache will be written after the program exits. The file name is optional,
in which case I<enable_cache> and I<enable_grep> must both be false.


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
