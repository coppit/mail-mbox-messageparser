#!/usr/bin/perl

# Test that we can process file handles for compressed and non-compressed
# files.

use strict;

use Test::More;
use lib 't';
use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Config;
use Mail::Mbox::MessageParser::Cache;
use Mail::Mbox::MessageParser::Grep;
use Mail::Mbox::MessageParser::Perl;
use File::Spec::Functions qw(:ALL);
use Test::Utils;
use FileHandle;

eval 'require Storable;';

my @files = <t/mailboxes/*.txt>;

mkdir catfile('t','temp'), 0700;

plan (tests => 4 * scalar (@files));

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  SKIP:
  {
    skip('bzip2 not available',4)
      if $filename =~ /\.bz2$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'bzip2'};
    skip('bzip not available',4)
      if $filename =~ /\.bz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'bzip'};
    skip('gzip not available',4)
      if $filename =~ /\.gz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'gzip'};
    skip('tzip not available',4)
      if $filename =~ /\.tz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'tzip'};
  
    TestImplementation($filename,0,0);

    skip('Storable not installed',2)
      unless defined $Storable::VERSION;

    InitializeCache($filename);

    TestImplementation($filename,1,0);
    TestImplementation($filename,1,1);

    skip('GNU grep not available',1)
      unless defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'};

    TestImplementation($filename,0,1);
  }
}

# ---------------------------------------------------------------------------

sub TestImplementation
{
  my $filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s/\.t//;

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

