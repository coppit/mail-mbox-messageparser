package Mail::Mbox::MessageParser::Grep;

no strict;

@ISA = qw( Exporter Mail::Mbox::MessageParser );

use strict;
use Carp;

use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Config;

use vars qw( $VERSION $DEBUG );
use vars qw( $CACHE );

$VERSION = sprintf "%d.%02d%02d", q/1.70.0/ =~ /(\d+)/g;

*CACHE = \$Mail::Mbox::MessageParser::MetaInfo::CACHE;

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $self) = @_;

  carp "Need file_name option" unless defined $self->{'file_name'};
  carp "Need file_handle option" unless defined $self->{'file_handle'};

  return "GNU grep not installed"
    unless defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'};

  bless ($self, __PACKAGE__);

  $self->_init();

  return $self;
}

#-------------------------------------------------------------------------------

sub _init
{
  my $self = shift;

  $self->SUPER::_init();

  $self->_initialize_cache_entry();
}

#-------------------------------------------------------------------------------

sub _initialize_cache_entry
{
  my $self = shift;
    
  my @stat = stat $self->{'file_name'};
      
  my $size = $stat[7];
  my $time_stamp = $stat[9];

  $CACHE->{$self->{'file_name'}}{'size'} = $size;
  $CACHE->{$self->{'file_name'}}{'time_stamp'} = $time_stamp;
  $CACHE->{$self->{'file_name'}}{'emails'} =
    _READ_GREP_DATA($self->{'file_name'});
}

#-------------------------------------------------------------------------------

sub _READ_GREP_DATA
{
  my $filename = shift;

  my @lines_and_offsets;

  dprint "Reading grep data";

  {
    my @grep_results;

    @grep_results = `unset LC_ALL LC_COLLATE LANG LC_CTYPE LC_MESSAGES; $Mail::Mbox::MessageParser::Config{'programs'}{'grep'} --extended-regexp --line-number --byte-offset --binary-files=text "^From [^:]+(:[0-9][0-9]){1,2}(  *([A-Z]{2,3}|[+-]?[0-9]{4})){1,3}( remote from .*)?\r?\$" "$filename"`;

    dprint "Read " . scalar(@grep_results) . " lines of grep data";

    foreach my $match_result (@grep_results)
    {
      my ($line_number, $byte_offset) = $match_result =~ /^(\d+):(\d+):/;
      push @lines_and_offsets,
        {'line number' => $line_number,'byte offset' => $byte_offset};
    }
  }

  my @emails;

  for(my $match_number = 0; $match_number <= $#lines_and_offsets; $match_number++)
  {
    if ($match_number == $#lines_and_offsets)
    {
      my $filesize = -s $filename;
      $emails[$match_number]{'length'} =
        $filesize - $lines_and_offsets[$match_number]{'byte offset'};
    }
    else
    {
      $emails[$match_number]{'length'} =
        $lines_and_offsets[$match_number+1]{'byte offset'} -
        $lines_and_offsets[$match_number]{'byte offset'};
    }

    $emails[$match_number]{'line_number'} =
      $lines_and_offsets[$match_number]{'line number'};

    $emails[$match_number]{'offset'} =
      $lines_and_offsets[$match_number]{'byte offset'};

    $emails[$match_number]{'validated'} = 0;
  }

  return \@emails;
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

sub read_next_email
{
  my $self = shift;

  my $last_email_index = $#{$CACHE->{$self->{'file_name'}}{'emails'}};

  if ($self->{'email_number'} <= $last_email_index)
  {
    $self->{'email_line_number'} =
      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'line_number'};
    $self->{'email_offset'} =
      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'offset'};
  }

  my $email = '';

  LOOK_FOR_NEXT_EMAIL:
  while ($self->{'email_number'} <= $last_email_index)
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

    if ($self->{'email_number'} == $last_email_index)
    {
      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'validated'} = 1;
      last LOOK_FOR_NEXT_EMAIL;
    }

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

    if ($end_of_string !~ /$endline$endline$/ ||
        $end_of_string =~
        /$endline-----(?: Begin Included Message |Original Message)-----$endline[^\r\n]*(?:$endline)*$/i ||
        $end_of_string =~
          /$endline--[^\r\n]*${endline}Content-type:[^\r\n]*$endline(?:[^\r\n]+:[^\r\n]+$endline)*$endline$/i)
    {
      dprint "Incorrect start of email found--adjusting cache data";

      $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}]{'length'} +=
        $CACHE->{$self->{'file_name'}}{'emails'}[$self->{'email_number'}+1]{'length'};

      if($self->{'email_number'}+2 <= $last_email_index)
      {
        @{$CACHE->{$self->{'file_name'}}{'emails'}}
          [$self->{'email_number'}+1..$last_email_index-1] =
            @{$CACHE->{$self->{'file_name'}}{'emails'}}
            [$self->{'email_number'}+2..$last_email_index];
      }

      pop @{$CACHE->{$self->{'file_name'}}{'emails'}};
      $last_email_index--;
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

  return \$email;
}

1;

__END__

# --------------------------------------------------------------------------

=head1 NAME

Mail::Mbox::MessageParser::Grep - A GNU grep-based mbox folder reader

=head1 SYNOPSIS

  #!/usr/bin/perl

  use Mail::Mbox::MessageParser;

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  my $folder_reader =
    new Mail::Mbox::MessageParser( {
      'file_name' => $filename,
      'file_handle' => $filehandle,
      'enable_grep' => 1,
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

This module implements a GNU grep-based mbox folder reader. It can only be
used when GNU grep is installed on the system. Users must not instantiate this
class directly--use Mail::Mbox::MessageParser instead. The base MessageParser
module will automatically manage the use of grep and non-grep implementations.

=head2 METHODS AND FUNCTIONS

The following methods and functions are specific to the
Mail::Mbox::MessageParser::Grep package. For additional inherited ones, see
the Mail::Mbox::MessageParser documentation.

=over 4

=item $ref = new( { 'file_name' => <mailbox file name>,
                    'file_handle' => <mailbox file handle>, });

    <file_name> - The full filename of the mailbox
    <file_handle> - An opened file handle for the mailbox

The constructor for the class takes two parameters. I<file_name> is the
filename of the mailbox.  The I<file_handle> argument is the opened file
handle to the mailbox. Both arguments are required.

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
