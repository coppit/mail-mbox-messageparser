#!/usr/bin/perl

# Test that we can process file handles for compressed and non-compressed
# files.

use strict;

use Test;
use lib 'lib';
use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Cache;
use Mail::Mbox::MessageParser::Grep;
use Mail::Mbox::MessageParser::Perl;
use File::Spec::Functions qw(:ALL);
use Test::Utils;
use FileHandle;

eval 'require Storable;';

my @files = <t/mailboxes/*.txt.*>;
@files = grep { !/non-mailbox/ } @files;

mkdir catfile('t','temp'), 0700;

plan (tests => 4 * scalar (@files));

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  if ($filename =~ /\.bz2$/ && !defined $PROGRAMS{'bzip2'})
  {
    skip('Skip bzip2 not available',1);
    skip('Skip bzip2 not available',1);
    skip('Skip bzip2 not available',1);
    skip('Skip bzip2 not available',1);
    next;
  }
  if ($filename =~ /\.bz$/ && !defined $PROGRAMS{'bzip'})
  {
    skip('Skip bzip not available',1);
    skip('Skip bzip not available',1);
    skip('Skip bzip not available',1);
    skip('Skip bzip not available',1);
    next;
  }
  if ($filename =~ /\.gz$/ && !defined $PROGRAMS{'gzip'})
  {
    skip('Skip gzip not available',1);
    skip('Skip gzip not available',1);
    skip('Skip gzip not available',1);
    skip('Skip gzip not available',1);
    next;
  }
  if ($filename =~ /\.tz$/ && !defined $PROGRAMS{'tzip'})
  {
    skip('Skip tzip not available',1);
    skip('Skip tzip not available',1);
    skip('Skip tzip not available',1);
    skip('Skip tzip not available',1);
    next;
  }

  TestImplementation($filename,0,0);

  if (defined $Storable::VERSION)
  {
    TestImplementation($filename,1,0);
    TestImplementation($filename,1,1);
  }
  else
  {
    skip('Skip Storable not installed',1);
    skip('Skip Storable not installed',1);
  }

  if (defined $Mail::Mbox::MessageParser::PROGRAMS{'grep'})
  {
    TestImplementation($filename,0,1);
  }
  else
  {
    skip('Skip GNU grep not available',1);
  }
}

# ---------------------------------------------------------------------------

sub TestImplementation
{
  my $filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s#\.t##;

  my ($folder_name) = $filename =~ /\/([^\/\\]*)\.txt.*$/;

  my $output_filename = catfile('t','temp',
    "${testname}_${folder_name}_${enable_cache}_${enable_grep}.stdout");

  my $output = new FileHandle(">$output_filename");
  binmode $output;

  my $filehandle = new FileHandle($filename);

  my $cache_file = catfile('t','temp','cache');

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => $cache_file})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $filehandle,
        'enable_cache' => $enable_cache,
        'enable_grep' => $enable_grep,
      } );

  die $folder_reader unless ref $folder_reader;

  my $prologue = $folder_reader->prologue;
  print $output $prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    my $email_text = $folder_reader->read_next_email();

    print $output $$email_text;
  }

  $output->close();

  $filename =~ s#\.(tz|bz2|gz)$##;

  CheckDiffs([$filename,$output_filename]);
}

# ---------------------------------------------------------------------------

