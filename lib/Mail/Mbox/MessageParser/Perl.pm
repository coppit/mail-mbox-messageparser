package Mail::Mbox::MessageParser::Perl;

no strict;

@ISA = qw( Exporter Mail::Mbox::MessageParser );

use strict;
use Mail::Mbox::MessageParser;

use vars qw( $VERSION $DEBUG $FROM_PATTERN );

$VERSION = '1.03';

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*FROM_PATTERN = \$Mail::Mbox::MessageParser::FROM_PATTERN;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

# Need this for a lookahead.
my $READ_CHUNK_SIZE = 20000;

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $options) = @_;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  die "Need file_handle option" unless defined $options->{'file_handle'};

  $self->{'file_handle'} = $options->{'file_handle'};

  $self->reset();

  $self->{'file_name'} = $options->{'file_name'};

  $self->{'READ_CHUNK_SIZE'} = $READ_CHUNK_SIZE;

  $self->_print_debug_information();

  return $self;
}

#-------------------------------------------------------------------------------

sub reset
{
  my $self = shift;

  if (defined $self->{'prologue'})
  {
    if (_IS_A_PIPE($self->{'file_handle'}))
    {
      dprint "Avoiding seek() on a pipe";
    }
    else
    {
      seek $self->{'file_handle'}, length($self->{'prologue'}), 0
    }

    $self->{'CURRENT_LINE_NUMBER'} = ($self->{'prologue'} =~ tr/\n//) + 1;
    $self->{'CURRENT_OFFSET'} = length($self->{'prologue'});
  }
  else
  {
    if (_IS_A_PIPE($self->{'file_handle'}))
    {
      dprint "Avoiding seek() on a pipe";
    }
    else
    {
      seek $self->{'file_handle'}, 0, 0;
    }

    $self->{'CURRENT_LINE_NUMBER'} = 1;
    $self->{'CURRENT_OFFSET'} = 0;
  }

  $self->{'READ_BUFFER'} = '';
  $self->{'START_OF_EMAIL'} = 0;
  $self->{'END_OF_EMAIL'} = 0;

  $self->{'end_of_file'} = 0;

  $self->{'email_line_number'} = 0;
  $self->{'email_offset'} = 0;
  $self->{'email_length'} = 0;
  $self->{'email_number'} = 0;
}

#-------------------------------------------------------------------------------

sub _IS_A_PIPE
{
  my $file_handle = shift;

  return (-t $file_handle || -S $file_handle ||
     -p $file_handle || !(seek $file_handle, 0, 1));
}

sub _read_prologue
{
  my $self = shift;

  dprint "Reading mailbox prologue";

  # Look for the start of the next email
  LOOK_FOR_FIRST_HEADER:
  if ($self->{'READ_BUFFER'} =~ m/$FROM_PATTERN/mg)
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

  dprint "Using Perl" if $DEBUG;

  $self->{'email_line_number'} = $self->{'CURRENT_LINE_NUMBER'};
  $self->{'email_offset'} = $self->{'CURRENT_OFFSET'};

  $self->{'START_OF_EMAIL'} = $self->{'END_OF_EMAIL'};

  # Look for the start of the next email
  LOOK_FOR_NEXT_HEADER:
  while ($self->{'READ_BUFFER'} =~ m/$FROM_PATTERN/mg)
  {
    $self->{'END_OF_EMAIL'} = pos($self->{'READ_BUFFER'}) - length($1);

    # Don't stop on email header for the first email in the buffer
    next unless $self->{'END_OF_EMAIL'};

    # Keep looking if the header we found is part of a "Begin Included
    # Message".
    my $end_of_string = substr($self->{'READ_BUFFER'}, $self->{'END_OF_EMAIL'}-200, 200);
    next if $end_of_string =~
        /\n-----(?: Begin Included Message |Original Message)-----\n[^\n]*\n*$/i;

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

  use Mail::Mbox::MessageParser::Perl;

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  my $folder_reader =
    new Mail::Mbox::MessageParser::Perl( {
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

This module implements a perl-based mbox folder reader. Users are encouraged
to use Mail::Mbox::MessageParser instead. The base MessageParser module will
automatically use a faster implementation is one is available. (Although you
can just use this module if you don't want to use caching or GNU grep.)

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
