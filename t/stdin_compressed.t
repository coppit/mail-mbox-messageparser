#!/usr/bin/perl

# Test that we can pipe compressed data to the module

use strict;
use warnings 'all';

use Test;
use Test::Utils;
use FileHandle;

my $installed = CheckInstalled();

my @files = <t/mailboxes/mail*.txt.*>;

mkdir 't/temp';

plan (tests => 1 * scalar (@files));

local $/ = undef;

my $test_program = <DATA>;

foreach my $filename (@files) 
{
  skip('Skip bzip2 not available',1)
    if $filename =~ /\.bz2$/ && !$installed->{'bzip'};
  skip('Skip gzip not available',1)
    if $filename =~ /\.gz$/ && !$installed->{'gzip'};
  skip('Skip tzip not available',1)
    if $filename =~ /\.tz$/ && !$installed->{'tzip'};

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
    "t/temp/${testname}_${folder_name}.testoutput";

  local $/ = undef;

  open TESTER, ">t/temp/stdin.pl";
  print TESTER $test_program;
  close TESTER;

  open MAILBOX, $filename;
  my $mailbox = <MAILBOX>;
  close MAILBOX;

  open PIPE, "|$^X -Iblib/lib t/temp/stdin.pl $output_filename";
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

  print $output_file_handle $folder_reader->prologue();

  while (!$folder_reader->{end_of_file})
  {
    my $email_text = $folder_reader->read_next_email();
    print $output_file_handle $$email_text;
  }

  close $output_file_handle;
}

################################################################################
