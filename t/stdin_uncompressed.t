#!/usr/bin/perl

# Test that we can pipe uncompressed mailboxes to STDIN

use strict;

use Test;
use lib 'lib';
use Test::Utils;
use FileHandle;

my @files = <t/mailboxes/*.txt>;

mkdir 't/temp', 0700;

plan (tests => 1 * scalar (@files));

local $/ = undef;

my $test_program = <DATA>;

foreach my $filename (@files) 
{
  TestImplementation($filename, $test_program);
}

# ---------------------------------------------------------------------------

sub TestImplementation
{
  my $filename = shift;
  my $test_program = shift;

  my $testname = $0;
  $testname =~ s/.*\///;
  $testname =~ s/\.t//;

  my ($folder_name) = $filename =~ /\/([^\/]*)\.txt.*$/;

  my $output_filename =
    "t/temp/${testname}_${folder_name}.stdout";

  local $/ = undef;

  open TESTER, ">t/temp/stdin.pl";
  print TESTER $test_program;
  close TESTER;

  open MAILBOX, $filename;
  my $mailbox = <MAILBOX>;
  close MAILBOX;

  open PIPE, "|$^X -Iblib/lib t/temp/stdin.pl '$output_filename'";
  local $SIG{PIPE} = sub { die "test program pipe broke" };
  print PIPE $mailbox;
  close PIPE;

  $filename =~ s/\.(tz|bz2|gz)$//;

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

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => undef,
        'file_handle' => $file_handle,
        'enable_cache' => 0,
        'enable_grep' => 0,
      } );

  die $folder_reader unless ref $folder_reader;

  print $output_file_handle $folder_reader->prologue();

  while (!$folder_reader->{end_of_file})
  {
    my $email_text = $folder_reader->read_next_email();
    print $output_file_handle $$email_text;
  }

  close $output_file_handle;
}

################################################################################
