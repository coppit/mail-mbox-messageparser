#!/usr/bin/perl

# Test that we can reset a file midway through parsing.

use strict;
use warnings 'all';

use Test;
use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Cache;
use Mail::Mbox::MessageParser::Grep;
use Mail::Mbox::MessageParser::Perl;
use Test::Utils;
use FileHandle;

my @files = <t/mailboxes/*.txt>;

mkdir 't/temp';

plan (tests => 6 * scalar (@files));

foreach my $filename (@files) 
{
  InitializeCache($filename);

  print "Testing partial mailbox reset with Perl implementation\n";
  TestPartialRead($filename,0,0);
  print "Testing partial mailbox reset with Cache implementation\n";
  TestPartialRead($filename,1,0);
  print "Testing partial mailbox reset with Grep implementation\n";
  TestPartialRead($filename,0,1);

  print "Testing full mailbox reset with Perl implementation\n";
  TestFullRead($filename,0,0);
  print "Testing full mailbox reset with Cache implementation\n";
  TestFullRead($filename,1,0);
  print "Testing full mailbox reset with Grep implementation\n";
  TestFullRead($filename,0,1);
}

# ---------------------------------------------------------------------------

sub TestPartialRead
{
  my $filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;

  my $testname = $0;
  $testname =~ s/.*\///;
  $testname =~ s/\.t//;

  my ($folder_name) = $filename =~ /\/([^\/]*)\.txt$/;

  my $output_filename =
    "t/temp/${testname}_${folder_name}_${enable_cache}_${enable_grep}.testoutput";

  my $output = new FileHandle(">$output_filename");

  my $filehandle = new FileHandle($filename);

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => 't/temp/cache'})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $filehandle,
        'enable_cache' => $enable_cache,
        'enable_grep' => $enable_grep,
      } );

  # Read just 1 email
  $folder_reader->read_next_email();

  $folder_reader->reset();

  print $output $folder_reader->prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    my $email = $folder_reader->read_next_email();
    print $output
      "number: " . $folder_reader->number() . "\n" .
      "line: " . $folder_reader->line_number() . "\n" .
      "offset: " . $folder_reader->offset() . "\n" .
      "bytes: " . $folder_reader->length() . "\n" .
      $$email;
  }

  $output->close();

  my $compare_filename = 
    "t/results/${testname}_${folder_name}.realoutput";

  CheckDiffs([$compare_filename,$output_filename]);
}

# ---------------------------------------------------------------------------

sub TestFullRead
{
  my $filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;

  my $testname = $0;
  $testname =~ s/.*\///;
  $testname =~ s/\.t//;

  my ($folder_name) = $filename =~ /\/([^\/]*)\.txt$/;

  my $output_filename =
    "t/temp/${testname}_${folder_name}_${enable_cache}_${enable_grep}.testoutput";

  my $output = new FileHandle(">$output_filename");

  my $filehandle = new FileHandle($filename);

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => 't/temp/cache'})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $filehandle,
        'enable_cache' => $enable_cache,
        'enable_grep' => $enable_grep,
      } );

  # Read whole mailbox
  while(!$folder_reader->end_of_file())
  {
    $folder_reader->read_next_email();
  }

  $folder_reader->reset();

  print $output $folder_reader->prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    my $email = $folder_reader->read_next_email();
    print $output
      "number: " . $folder_reader->number() . "\n" .
      "line: " . $folder_reader->line_number() . "\n" .
      "offset: " . $folder_reader->offset() . "\n" .
      "bytes: " . $folder_reader->length() . "\n" .
      $$email;
  }

  $output->close();

  my $compare_filename = 
    "t/results/${testname}_${folder_name}.realoutput";

  CheckDiffs([$compare_filename,$output_filename]);
}

# ---------------------------------------------------------------------------

