package Mail::Mbox::MessageParser::Cache;

no strict;

@ISA = qw( Exporter Mail::Mbox::MessageParser );

use strict;
use Carp;

use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::MetaInfo;

use vars qw( $VERSION $DEBUG );
use vars qw( $CACHE );

$VERSION = sprintf "%d.%02d%02d", q/1.30.0/ =~ /(\d+)/g;

*CACHE = \$Mail::Mbox::MessageParser::MetaInfo::CACHE;
*WRITE_CACHE = \&Mail::Mbox::MessageParser::MetaInfo::WRITE_CACHE;
*INITIALIZE_ENTRY = \&Mail::Mbox::MessageParser::MetaInfo::INITIALIZE_ENTRY;
sub WRITE_CACHE;
sub INITIALIZE_ENTRY;

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $self) = @_;

  carp "Need file_name option" unless defined $self->{'file_name'};
  carp "Need file_handle option" unless defined $self->{'file_handle'};

  carp "Call SETUP_CACHE() before calling new()"
    unless exists $Mail::Mbox::MessageParser::MetaInfo::CACHE_OPTIONS{'file_name'};

  bless ($self, __PACKAGE__);

  $self->_init();

  return $self;
}

#-------------------------------------------------------------------------------

sub _init
{
  my $self = shift;

  WRITE_CACHE();

  $self->SUPER::_init();

  INITIALIZE_ENTRY($self->{'file_name'});
}

#-------------------------------------------------------------------------------

sub reset
{
  my $self = shift;

  $self->SUPER::reset();

  # If we're in the middle of parsing this file, we need to reset the cache
  INITIALIZE_ENTRY($self->{'file_name'});
}

#-------------------------------------------------------------------------------

sub _read_prologue
{
  my $self = shift;

  dprint "Reading mailbox prologue using grep";

  my $prologue_length = $CACHE->{$self->{'file_name'}}{'emails'}[0]{'offset'};

  my $bytes_read = 0;
  do {
    $bytes_read += read($self->{'file_handle'}, $self->{'prologue'},
      $prologue_length-$bytes_read, $bytes_read);
  } while ($bytes_read != $prologue_length);
}

#-------------------------------------------------------------------------------

sub _print_debug_information
{
  return unless $DEBUG;

  my $self = shift;

  $self->SUPER::_print_debug_information();

  dprint "Valid cache entry exists: " .
    ($#{ $CACHE->{$self->{'file_name'}}{'emails'} } != -1 ? "Yes" : "No");
}

#-------------------------------------------------------------------------------

sub read_next_email
{
  my $self = shift;

  $self->{'email_line_number'} =
    $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'line_number'};
  $self->{'email_offset'} =
    $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'offset'};

  my $email = '';

  LOOK_FOR_NEXT_EMAIL:
  while ($self->{'email_number'} <=
      $#{$CACHE->{$self->{'file_name'}}{'emails'}})
  {
    $self->{'email_length'} =
      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'length'};

    {
      my $bytes_read = length($email);
      do {
        $bytes_read += read($self->{'file_handle'},
          $email, $self->{'email_length'}-$bytes_read, $bytes_read);
      } while ($bytes_read != $self->{'email_length'});
    }

    last LOOK_FOR_NEXT_EMAIL
      if $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'validated'};

    my $endline = $self->{'endline'};

    # Keep looking if the header we found is part of a "Begin Included
    # Message".
    my $end_of_string = '';
    my $backup_amount = 100;
    do
    {
      $backup_amount *= 2;
      $end_of_string = substr($email, -$backup_amount);
    } while (index($end_of_string, "$endline$endline") == -1 &&
      $backup_amount < $self->{'email_length'});

    if ($end_of_string =~
        /$endline-----(?: Begin Included Message |Original Message)-----$endline[^\r\n]*(?:$endline)*$/i ||
        $end_of_string =~
          /$endline--[^\r\n]*${endline}Content-type:[^\r\n]*$endline$endline/i)
    {
      dprint "Incorrect start of email found--adjusting cache data";

      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'length'} +=
        $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}+1]{'length'};

      my $last_email_index = $#{$CACHE->{$self->{'file_name'}}{'emails'}};

      if($self->{'email_number'}+2 <= $last_email_index)
      {
        @{$CACHE->{$self->{'file_name'}}{'emails'}}
          [$self->{'email_number'}+1..$last_email_index-1] =
            @{$CACHE->{$self->{'file_name'}}{'emails'}}
            [$self->{'email_number'}+2..$last_email_index];
      }

      pop @{$CACHE->{$self->{'file_name'}}{'emails'}};
    }
    else
    {
      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'validated'} = 1;
      last LOOK_FOR_NEXT_EMAIL;
    }
  }

  $self->{'end_of_file'} = 1 if eof $self->{'file_handle'};

  $self->{'email_number'}++;

  $self->SUPER::read_next_email();

  $Mail::Mbox::MessageParser::MetaInfo::UPDATING_CACHE = 0
    if $self->{'email_number'} - 1 ==
      $#{ $CACHE->{$self->{'file_name'}}{'emails'} };

  return \$email;
}

1;

__END__

# --------------------------------------------------------------------------

=head1 NAME

Mail::Mbox::MessageParser::Cache - A cache-based mbox folder reader

=head1 SYNOPSIS

  #!/usr/bin/perl

  use Mail::Mbox::MessageParser;

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  # Set up cache
  Mail::Mbox::MessageParser::SETUP_CACHE(
    { 'file_name' => '/tmp/cache' } );

  my $folder_reader =
    new Mail::Mbox::MessageParser( {
      'file_name' => $filename,
      'file_handle' => $filehandle,
      'enable_cache' => 1,
    } );

  die $folder_reader unless ref $folder_reader;
  
  warn "No cached information"
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
when cache information already exists. Users must not instantiate this class
directly--use Mail::Mbox::MessageParser instead. The base MessageParser module
will automatically manage the use of cache and non-cache implementations.

=head2 METHODS AND FUNCTIONS

The following methods and functions are specific to the
Mail::Mbox::MessageParser::Cache package. For additional inherited ones, see
the Mail::Mbox::MessageParser documentation.

=over 4

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

Mail::Mbox::MessageParser

=cut
