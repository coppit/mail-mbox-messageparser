package Test::Utils;

use strict;
use Exporter;
use Test;

use vars qw( @EXPORT @ISA );
use Mail::Mbox::MessageParser;

@ISA = qw( Exporter );
@EXPORT = qw( CheckDiffs DoDiff InitializeCache CheckInstalled );

sub CheckDiffs
{
  my @pairs = @_;

  foreach my $pair (@pairs)
  {
    my $filename = $pair->[0];
    my $output_filename = $pair->[1];

    my ($diff,$result) = DoDiff($filename,$output_filename);

    ok(0), return if $diff == 0;
    ok(0), return if $result == 0;
  }

  ok(1), return;
}

# ---------------------------------------------------------------------------

# Returns the results of the diff, and the results of the test.

sub DoDiff
{
  my $filename = shift;
  my $output_filename = shift;

  my $diffstring = "diff $output_filename $filename";

  system "echo $diffstring > $output_filename.diff ".
    "2>$output_filename.diff.error";

  system "$diffstring >> $output_filename.diff ".
    "2>$output_filename.diff.error";

  open DIFF_ERR, "$output_filename.diff.error";
  my $diff_err = join '', <DIFF_ERR>;
  close DIFF_ERR;

  unlink "$output_filename.diff.error";

  if ($? == 2)
  {
    print "Couldn't do diff on results.\n";
    return (0,undef);
  }

  if ($diff_err ne '')
  {
    print $diff_err;
    return (0,undef);
  }

  local $/ = "\n";

  my @diffs = `cat $output_filename.diff`;
  shift @diffs;
  my $numdiffs = ($#diffs + 1) / 2;

  if ($numdiffs != 0)
  {
    print "Failed, with $numdiffs differences.\n";
    print "  See $output_filename and " .
      "$output_filename.diff.\n";
    return (1,0);
  }

  if ($numdiffs == 0)
  {
    print "Output looks good.\n";

    unlink "$output_filename";
    unlink "$output_filename.diff";
    return (1,1);
  }
}

# ---------------------------------------------------------------------------

sub InitializeCache
{
  my $filename = shift;

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => 't/temp/cache'});
  Mail::Mbox::MessageParser::CLEAR_CACHE();

  my $filehandle = new FileHandle($filename);

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $filehandle,
        'enable_cache' => 1,
        'enable_grep' => 0,
      } );

  my $prologue = $folder_reader->prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    $folder_reader->read_next_email();
  }

  $filehandle->close();

  Mail::Mbox::MessageParser::WRITE_CACHE();
}

# ---------------------------------------------------------------------------

sub CheckInstalled
{
  # Save old STDERR and redirect temporarily to nothing. This will prevent the
  # test script from emitting a warning if the backticks can't find the
  # compression programs
  use vars qw(*OLDSTDERR);
  open OLDSTDERR,">&STDERR" or die "Can't save STDERR: $!\n";
  open STDERR,">/dev/null" or die "Can't redirect STDERR to /dev/null: $!\n";

  my %return = (
    'gzip' => 0,
    'bzip' => 0,
    'tzip' => 0,
  );

  my $temp = `bzip2 -h 2>&1`;
  $return{'bzip'} = 1 if $temp =~ /usage/;

  $temp = `gzip -h 2>&1`;
  $return{'gzip'} = 1 if $temp =~ /usage/;

  $temp = `tzip -h 2>&1`;
  $return{'tzip'} = 1 if $temp =~ /usage/;

  open STDERR,">&OLDSTDERR" or die "Can't restore STDERR: $!\n";

  return \%return;
}

1;
