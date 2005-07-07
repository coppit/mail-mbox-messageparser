package Mail::Mbox::MessageParser::Perl;

no strict;

@ISA = qw( Exporter Mail::Mbox::MessageParser );

use strict;
use Carp;

use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Config;

use vars qw( $VERSION $DEBUG );

$VERSION = sprintf "%d.%02d%02d", q/1.60.0/ =~ /(\d+)/g;

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $self) = @_;

  carp "Need file_handle option" unless defined $self->{'file_handle'};

  bless ($self, __PACKAGE__);

  $self->_init();

  return $self;
}

#-------------------------------------------------------------------------------

sub _init
{
  my $self = shift;

  $self->{'READ_CHUNK_SIZE'} =
    $Mail::Mbox::MessageParser::Config{'read_chunk_size'};

  $self->{'CURRENT_LINE_NUMBER'} = 1;
  $self->{'CURRENT_OFFSET'} = 0;

  $self->{'READ_BUFFER'} = '';
  $self->{'START_OF_EMAIL'} = 0;
  $self->{'END_OF_EMAIL'} = 0;

  $self->SUPER::_init();
}

#-------------------------------------------------------------------------------

sub reset
{
  my $self = shift;

  $self->{'CURRENT_LINE_NUMBER'} = ($self->{'prologue'} =~ tr/\n//) + 1;
  $self->{'CURRENT_OFFSET'} = length($self->{'prologue'});

  $self->{'READ_BUFFER'} = '';
  $self->{'START_OF_EMAIL'} = 0;
  $self->{'END_OF_EMAIL'} = 0;

  $self->SUPER::reset();
}

#-------------------------------------------------------------------------------

sub _read_prologue
{
  my $self = shift;

  dprint "Reading mailbox prologue using Perl";

  # Look for the start of the next email
  LOOK_FOR_FIRST_HEADER:
  if ($self->{'READ_BUFFER'} =~
      m/$Mail::Mbox::MessageParser::Config{'from_pattern'}/mg)
  {
    my $start_of_email = pos($self->{'READ_BUFFER'}) - length($1);

    if ($start_of_email == 0)
    {
      $self->{'prologue'} = '';
      return;
    }

    $self->{'prologue'} = substr($self->{'READ_BUFFER'}, 0, $start_of_email);

    $self->{'CURRENT_LINE_NUMBER'} += ($self->{'prologue'} =~ tr/\n//);
    $self->{'CURRENT_OFFSET'} = $start_of_email;
    $self->{'END_OF_EMAIL'} = $start_of_email;

    return;
  }

  # Didn't find next email in current buffer. Most likely we need to read some
  # more of the mailbox.

  # Start looking at the end of the buffer, but back up some in case the edge
  # of the newly read buffer contains the start of a new header. I believe the
  # RFC says header lines can be at most 90 characters long.
  my $search_position = length($self->{'READ_BUFFER'}) - 90;
  $search_position = 0 if $search_position < 0;

  local $/ = undef;

  # Can't use sysread because it doesn't work with ungetc
  if ($self->{'READ_CHUNK_SIZE'} == 0)
  {
    local $/ = undef;

    if (eof $self->{'file_handle'})
    {
      $self->{'end_of_file'} = 1;

      $self->{'prologue'} = $self->{'READ_BUFFER'};
      return;
    }
    else
    {
      # < $self->{'file_handle'} > doesn't work, so we use readline
      $self->{'READ_BUFFER'} = readline($self->{'file_handle'});
      pos($self->{'READ_BUFFER'}) = $search_position;
      goto LOOK_FOR_FIRST_HEADER;
    }
  }
  else
  {
    if (read($self->{'file_handle'}, $self->{'READ_BUFFER'},
      $self->{'READ_CHUNK_SIZE'}, length($self->{'READ_BUFFER'})))
    {
      pos($self->{'READ_BUFFER'}) = $search_position;
      $self->{'READ_CHUNK_SIZE'} *= 2;
      goto LOOK_FOR_FIRST_HEADER;
    }
    else
    {
      $self->{'end_of_file'} = 1;

      $self->{'prologue'} = $self->{'READ_BUFFER'};
      return;
    }
  }
}

#-------------------------------------------------------------------------------

sub read_next_email
{
  my $self = shift;

  $self->{'email_line_number'} = $self->{'CURRENT_LINE_NUMBER'};
  $self->{'email_offset'} = $self->{'CURRENT_OFFSET'};

  $self->{'START_OF_EMAIL'} = $self->{'END_OF_EMAIL'};

  # Look for the start of the next email
  LOOK_FOR_NEXT_HEADER:
  while ($self->{'READ_BUFFER'} =~
      m/$Mail::Mbox::MessageParser::Config{'from_pattern'}/mg)
  {
    $self->{'END_OF_EMAIL'} = pos($self->{'READ_BUFFER'}) - length($1);

    # Don't stop on email header for the first email in the buffer
    next unless $self->{'END_OF_EMAIL'};

    my $endline = $self->{'endline'};

    # Keep looking if the header we found is part of a "Begin Included
    # Message".
    my $end_of_string = '';
    my $backup_amount = 100;
    do
    {
      $backup_amount *= 2;
      $end_of_string = substr($self->{'READ_BUFFER'},
        $self->{'END_OF_EMAIL'}-$backup_amount, $backup_amount);
    } while (index($end_of_string, "$endline$endline") == -1 &&
      $backup_amount < $self->{'END_OF_EMAIL'});

    next if $end_of_string =~
        /$endline-----(?: Begin Included Message |Original Message)-----$endline[^\r\n]*(?:$endline)*$/i;

    next if $end_of_string =~
      /$endline--[^\r\n]*${endline}Content-type:[^\r\n]*$endline(?:[^\r\n]+:[^\r\n]+$endline)*$endline$/i;

    next unless $end_of_string =~ /$endline$endline$/;

    # Found the next email!
    $self->{'email_length'} = $self->{'END_OF_EMAIL'}-$self->{'START_OF_EMAIL'};
    my $email = substr($self->{'READ_BUFFER'}, $self->{'START_OF_EMAIL'},
      $self->{'email_length'});
    $self->{'CURRENT_LINE_NUMBER'} += ($email =~ tr/\n//);
    $self->{'CURRENT_OFFSET'} += $self->{'email_length'};

    $self->{'email_number'}++;

    $self->SUPER::read_next_email();

    return \$email;
  }

  # Didn't find next email in current buffer. Most likely we need to read some
  # more of the mailbox. Shift the current email to the front of the buffer
  # unless we've already done so.
  substr($self->{'READ_BUFFER'},0,$self->{'START_OF_EMAIL'}) = '';
  $self->{'START_OF_EMAIL'} = 0;

  # Start looking at the end of the buffer, but back up some in case the edge
  # of the newly read buffer contains the start of a new header. I believe the
  # RFC says header lines can be at most 90 characters long.
  my $search_position = length($self->{'READ_BUFFER'}) - 90;
  $search_position = 0 if $search_position < 0;

  # Can't use sysread because it doesn't work with ungetc
  if ($self->{'READ_CHUNK_SIZE'} == 0)
  {
    local $/ = undef;

    if (eof $self->{'file_handle'})
    {
      $self->{'end_of_file'} = 1;

      $self->{'email_length'} = length($self->{'READ_BUFFER'});
      $self->{'email_number'}++;

      $self->SUPER::read_next_email();

      return \$self->{'READ_BUFFER'};
    }
    else
    {
      # < $self->{'file_handle'} > doesn't work, so we use readline
      $self->{'READ_BUFFER'} = readline($self->{'file_handle'});
      pos($self->{'READ_BUFFER'}) = $search_position;
      goto LOOK_FOR_NEXT_HEADER;
    }
  }
  else
  {
    if (read($self->{'file_handle'}, $self->{'READ_BUFFER'},
      $self->{'READ_CHUNK_SIZE'}, length($self->{'READ_BUFFER'})))
    {
      pos($self->{'READ_BUFFER'}) = $search_position;
      $self->{'READ_CHUNK_SIZE'} *= 2;
      goto LOOK_FOR_NEXT_HEADER;
    }
    else
    {
      $self->{'end_of_file'} = 1;

      $self->{'email_length'} = length($self->{'READ_BUFFER'});
      $self->{'email_number'}++;

      $self->SUPER::read_next_email();

      return \$self->{'READ_BUFFER'};
    }
  }
}

1;

__END__

# --------------------------------------------------------------------------

=head1 NAME

Mail::Mbox::MessageParser::Perl - A Perl-based mbox folder reader

=head1 SYNOPSIS

  #!/usr/bin/perl

  use Mail::Mbox::MessageParser;

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  my $folder_reader =
    new Mail::Mbox::MessageParser( {
      'file_name' => $filename,
      'file_handle' => $filehandle,
    } );

  die $folder_reader unless ref $folder_reader;
  
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

This module implements a Perl-based mbox folder reader.  Users must not
instantiate this class directly--use Mail::Mbox::MessageParser instead. The
base MessageParser module will automatically manage the use of faster
implementations if they can be used.

=head2 METHODS AND FUNCTIONS

The following methods and functions are specific to the
Mail::Mbox::MessageParser::Perl package. For additional inherited ones, see
the Mail::Mbox::MessageParser documentation.

=over 4

=item $ref = new( { 'file_name' => <mailbox file name>,
                    'file_handle' => <mailbox file handle> });

    <file_name> - The full filename of the mailbox
    <file_handle> - An opened file handle for the mailbox

The constructor for the class takes two parameters. The optional I<file_name>
parameter is the filename of the mailbox. The required I<file_handle> argument
is the opened file handle to the mailbox. 

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
