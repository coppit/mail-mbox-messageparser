#!/usr/bin/perl

use strict;
use warnings 'all';

use Test;
use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Cache;
use Mail::Mbox::MessageParser::Grep;
use Mail::Mbox::MessageParser::Perl;
use Test::Utils;
use FileHandle;

my $installed = CheckInstalled();

my @files = <t/mailboxes/mailarc-*.txt>;

mkdir 't/temp';

plan (tests => 1 * scalar (@files));

foreach my $filename (@files) 
{
  skip('Skip bzip2 not available',1)
    if $filename =~ /\.bz2$/ && !$installed->{'bzip'};
  skip('Skip gzip not available',1)
    if $filename =~ /\.gz$/ && !$installed->{'gzip'};
  skip('Skip tzip not available',1)
    if $filename =~ /\.tz$/ && !$installed->{'tzip'};

  TestImplementation($filename,0,0);
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

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => 't/temp/cache'})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => undef,
        'enable_cache' => $enable_cache,
        'enable_grep' => $enable_grep,
      } );

  my $prologue = $folder_reader->prologue;
  print $output $prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    my $email_text = $folder_reader->read_next_email();

    print $output $$email_text;
  }

  $output->close();

  CheckDiffs([$filename,$output_filename]);
}
