package Mail::Mbox::MessageParser::Grep;

no strict;

@ISA = qw( Exporter Mail::Mbox::MessageParser );

use strict;
use Mail::Mbox::MessageParser;
use Carp;

use vars qw( $VERSION $DEBUG $GREP_DATA );

$VERSION = '1.04';

$GREP_DATA = {};

*DEBUG = \$Mail::Mbox::MessageParser::DEBUG;
*dprint = \&Mail::Mbox::MessageParser::dprint;
sub dprint;

#-------------------------------------------------------------------------------

sub new
{
  my ($proto, $options) = @_;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  carp "Need file_name option" unless defined $options->{'file_name'};
  carp "Need file_handle option" unless defined $options->{'file_handle'};

  return "GNU grep not installed"
    unless defined $Mail::Mbox::MessageParser::PROGRAMS{'grep'};

  $self->{'file_handle'} = undef;
  $self->{'file_handle'} = $options->{'file_handle'}
    if exists $options->{'file_handle'};

  $self->{'file_name'} = $options->{'file_name'};
  $self->{'file_name'} = $options->{'file_name'};
  $self->{'force_processing'} = $options->{'force_processing'}
    if exists $options->{'force_processing'};

  $self->reset();

  _READ_GREP_DATA($self->{'file_name'},$self->{'force_processing'})
    unless defined $GREP_DATA->{$self->{'file_name'}};

  return "Couldn't read grep data"
    unless defined $GREP_DATA->{$self->{'file_name'}};

  return $self;
}

#-------------------------------------------------------------------------------

sub reset
{
  my $self = shift;

  seek $self->{'file_handle'}, length($self->{'prologue'}), 0
    if defined $self->{'file_handle'} && defined $self->{'prologue'};

  $self->{'end_of_file'} = 0;

  $self->{'email_line_number'} = 0;
  $self->{'email_offset'} = 0;
  $self->{'email_length'} = 0;
  $self->{'email_number'} = 0;
}

#-------------------------------------------------------------------------------

sub _read_prologue
{
  my $self = shift;

  dprint "Reading mailbox prologue using grep";

  my $prologue_length = $GREP_DATA->{$self->{'file_name'}}{'offsets'}[0];
  my $bytes_read = 0;

  do
  {
    $bytes_read += read($self->{'file_handle'}, $self->{'prologue'},
      $prologue_length-$bytes_read, $bytes_read);
  } while ($bytes_read != $prologue_length);
}

#-------------------------------------------------------------------------------

sub _READ_GREP_DATA
{
  my $filename = shift;
  my $force_processing = shift;

  my @lines_and_offsets;

  dprint "Reading grep data";

  {
    my @grep_results;
    
    if ($force_processing)
    {
      @grep_results = `$Mail::Mbox::MessageParser::PROGRAMS{'grep'} --extended-regexp --line-number --byte-offset --binary-files=text "^(X-Draft-From: .*|X-From-Line: .*|From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?)\r?\$" "$filename"`;
    }
    else
    {
      @grep_results = `$Mail::Mbox::MessageParser::PROGRAMS{'grep'} --extended-regexp --line-number --byte-offset "^(X-Draft-From: .*|X-From-Line: .*|From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?)\r?\$" "$filename"`;
    }

    dprint "Read " . scalar(@grep_results) . " lines of grep data";

    foreach my $match_result (@grep_results)
    {
      my ($line_number, $byte_offset) = $match_result =~ /^(\d+):(\d+):/;
      push @lines_and_offsets,
        {'line number' => $line_number,'byte offset' => $byte_offset};
    }
  }

  for(my $match_number = 0; $match_number <= $#lines_and_offsets; $match_number++)
  {
    if ($match_number == $#lines_and_offsets)
    {
      my $filesize = -s $filename; $GREP_DATA->{$filename}{'lengths'}[$match_number] =
        $filesize - $lines_and_offsets[$match_number]{'byte offset'};
    }
    else
    {
      $GREP_DATA->{$filename}{'lengths'}[$match_number] =
        $lines_and_offsets[$match_number+1]{'byte offset'} -
        $lines_and_offsets[$match_number]{'byte offset'};
    }

    $GREP_DATA->{$filename}{'line_numbers'}[$match_number] =
      $lines_and_offsets[$match_number]{'line number'};

    $GREP_DATA->{$filename}{'offsets'}[$match_number] =
      $lines_and_offsets[$match_number]{'byte offset'};

    $GREP_DATA->{$filename}{'validated'}[$match_number] = 0;
  }
}

#-------------------------------------------------------------------------------

sub read_next_email
{
  my $self = shift;

  $self->{'email_line_number'} =
    $GREP_DATA->{$self->{'file_name'}}{'line_numbers'}[$self->{'email_number'}];
  $self->{'email_offset'} =
    $GREP_DATA->{$self->{'file_name'}}{'offsets'}[$self->{'email_number'}];

  my $email = '';

  LOOK_FOR_NEXT_EMAIL:
  while ($self->{'email_number'} <=
      $#{$GREP_DATA->{$self->{'file_name'}}{'lengths'}})
  {
    $self->{'email_length'} =
      $GREP_DATA->{$self->{'file_name'}}{'lengths'}[$self->{'email_number'}];

    {
      my $bytes_read = length($email);
      do {
        $bytes_read += read($self->{'file_handle'},
          $email, $self->{'email_length'}-$bytes_read, $bytes_read);
      } while ($bytes_read != $self->{'email_length'});
    }

    last LOOK_FOR_NEXT_EMAIL
      if $GREP_DATA->{$self->{'file_name'}}{'validated'}[$self->{'email_number'}];

    # Keep looking if the header we found is part of a "Begin Included
    # Message".
    my $end_of_string = substr($email, -200);
    my $endline = $self->{'endline'};
    if ($end_of_string =~
        /$endline-----(?: Begin Included Message |Original Message)-----$endline[^\r\n]*(?:$endline)*$/i)
    {
      dprint "Incorrect start of email found--adjusting grep data";

      $GREP_DATA->{$self->{'file_name'}}{'lengths'}[$self->{'email_number'}] +=
        $GREP_DATA->{$self->{'file_name'}}{'lengths'}[$self->{'email_number'}+1];

      my $last_email_index = $#{$GREP_DATA->{$self->{'file_name'}}{'lengths'}};

      if($self->{'email_number'}+2 <= $last_email_index)
      {
        @{$GREP_DATA->{$self->{'file_name'}}{'lengths'}}
          [$self->{'email_number'}+1..$last_email_index-1] =
            @{$GREP_DATA->{$self->{'file_name'}}{'lengths'}}
            [$self->{'email_number'}+2..$last_email_index];

        @{$GREP_DATA->{$self->{'file_name'}}{'line_numbers'}}
          [$self->{'email_number'}+1..$last_email_index-1] =
            @{$GREP_DATA->{$self->{'file_name'}}{'line_numbers'}}
            [$self->{'email_number'}+2..$last_email_index];

        @{$GREP_DATA->{$self->{'file_name'}}{'offsets'}}
          [$self->{'email_number'}+1..$last_email_index-1] =
            @{$GREP_DATA->{$self->{'file_name'}}{'offsets'}}
            [$self->{'email_number'}+2..$last_email_index];
      }

      pop @{$GREP_DATA->{$self->{'file_name'}}{'lengths'}};
      pop @{$GREP_DATA->{$self->{'file_name'}}{'line_numbers'}};
      pop @{$GREP_DATA->{$self->{'file_name'}}{'offsets'}};
    }
    else
    {
      $GREP_DATA->{$self->{'file_name'}}{'validated'}[$self->{'email_number'}] = 1;
      last LOOK_FOR_NEXT_EMAIL;
    }
  }

  $self->{'end_of_file'} = 1
    if $self->{'email_number'} == 
      $#{$GREP_DATA->{$self->{'file_name'}}{'lengths'}};

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

  use Mail::Mbox::MessageParser::Grep;

  my $filename = 'mail/saved-mail';
  my $filehandle = new FileHandle($filename);

  my $folder_reader =
    new Mail::Mbox::MessageParser::Grep( {
      'file_name' => $filename,
      'file_handle' => $filehandle,
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

This module implements a GNU grep-based mbox folder reader. It can only be
used when GNU grep is installed on the system. Users are encouraged to use
Mail::Mbox::MessageParser instead. The base MessageParser module will
automatically fall back to another reader implementation if this module can
not be used.

=head2 METHODS AND FUNCTIONS

The following methods and functions are specific to the
Mail::Mbox::MessageParser::Grep package. For additional inherited ones, see
the Mail::Mbox::MessageParser documentation.

=over 4

=item $ref = new( { 'file_name' => <mailbox file name>,
                    'file_handle' => <mailbox file handle>,
                    'force_processing' => <1 or 0>, });

    <file_name> - The full filename of the mailbox
    <file_handle> - An opened file handle for the mailbox
    <force_processing> - true to force processing of files that look invalid

The constructor for the class takes two parameters. I<file_name> is the
filename of the mailbox.  The I<file_handle> argument is the opened file
handle to the mailbox. Both arguments are required.

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
