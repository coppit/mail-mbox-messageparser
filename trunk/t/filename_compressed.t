#!/usr/bin/perl

# Test that the module will correctly open a compressed filename

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

my @files = <t/mailboxes/*.txt.*>;
@files = grep { !/non-mailbox/ } @files;

mkdir catfile('t','temp'), 0700;

plan (tests => 1 * scalar (@files));

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  if ($filename =~ /\.bz2$/ && !defined $PROGRAMS{'bzip2'})
  {
    skip('Skip bzip2 not available',1);
    next;
  }
  if ($filename =~ /\.bz$/ && !defined $PROGRAMS{'bzip'})
  {
    skip('Skip bzip not available',1);
    next;
  }
  if ($filename =~ /\.gz$/ && !defined $PROGRAMS{'gzip'})
  {
    skip('Skip gzip not available',1);
    next;
  }
  if ($filename =~ /\.tz$/ && !defined $PROGRAMS{'tzip'})
  {
    skip('Skip tzip not available',1);
    next;
  }

  TestImplementation($filename,0,0);
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

  my $cache_file = catfile('t','temp','cache');

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => $cache_file})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => undef,
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

