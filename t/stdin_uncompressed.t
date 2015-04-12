#!/usr/bin/perl

# Test that we can pipe uncompressed mailboxes to STDIN

use strict;

use Test::More;
use lib 't';
use File::Spec::Functions qw(:ALL);
use Test::Utils;
use FileHandle;
use File::Slurp;

my @files = <t/mailboxes/*.txt>;

mkdir catfile('t','temp'), 0700;

plan (tests => 1 * scalar (@files));

my $test_program = read_file(\*DATA);

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  TestImplementation($filename, $test_program);
}

# ---------------------------------------------------------------------------

sub TestImplementation
{
  my $filename = shift;
  my $test_program = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s#\.t##;

  my ($folder_name) = $filename =~ /\/([^\/\\]*)\.txt.*$/;

  my $output_filename = catfile('t','temp',
    "${testname}_${folder_name}.stdout");

  local $/ = undef;

  write_file(catfile('t','temp','stdin.pl'), {binmode => ':raw'}, $test_program);

  my $mailbox = read_file($filename, { binmode => ':raw' });

  open PIPE, "|$^X -I" . catfile('blib','lib') . " " .
    catfile('t','temp','stdin.pl') . " \"$output_filename\"";
  binmode PIPE;
  local $SIG{PIPE} = sub { die "test program pipe broke" };
  print PIPE $mailbox;
  close PIPE;

  $filename =~ s#\.(tz|bz2|gz)$##;

  CheckDiffs([$filename,$output_filename]);
}

################################################################################

__DATA__

use strict;
use Mail::Mbox::MessageParser;
use FileHandle;

die unless @ARGV == 1;

my $output_filename = shift @ARGV;

my $fileHandle = new FileHandle;
$fileHandle->open('-');

ParseFile($output_filename);

exit;

################################################################################

sub ParseFile
{
  my $output_filename = shift;

  my $file_handle = new FileHandle;
  $file_handle->open('-') or die $!;

  my $output_file_handle = new FileHandle(">$output_filename");
  binmode $output_file_handle;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => undef,
        'file_handle' => $file_handle,
        'enable_cache' => 0,
        'enable_grep' => 0,
        'debug' => $ENV{TEST_VERBOSE},
      } );

  die $folder_reader unless ref $folder_reader;

  print $output_file_handle $folder_reader->prologue();

  while (!$folder_reader->end_of_file())
  {
    my $email_text = $folder_reader->read_next_email();
    print $output_file_handle $$email_text;
  }

  close $output_file_handle;
}

################################################################################
