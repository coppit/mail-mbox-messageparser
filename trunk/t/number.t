#!/usr/bin/perl

# Test that every email read has the right starting index number.

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

plan (tests => 3 * scalar (@files));

foreach my $filename (@files) 
{
  InitializeCache($filename);

  TestImplementation($filename,0,0);
  TestImplementation($filename,1,0);
  TestImplementation($filename,0,1);
}

# ---------------------------------------------------------------------------

sub TestImplementation
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

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    $folder_reader->read_next_email();

    print $output $folder_reader->number() . "\n";
  }

  $output->close();

  my $compare_filename = 
    "t/results/${testname}_${folder_name}.realoutput";

  CheckDiffs([$compare_filename,$output_filename]);
}

# ---------------------------------------------------------------------------

