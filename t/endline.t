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

my @files = <t/mailboxes/mailarc-1*.txt>;

mkdir catfile('t','temp'), 0700;

plan (tests => 4 * scalar (@files));

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  TestImplementation($filename,0,0);

  if (defined $Storable::VERSION)
  {
    InitializeCache($filename);

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

  if ($filename =~ /-dos/)
  {
    if ($folder_reader->endline() eq "\r\n")
    {
      ok(1);
    }
    else
    {
      ok(0); # Not a dos endline as expected
    }
  }
  else
  {
    if ($folder_reader->endline() eq "\n")
    {
      ok(1);
    }
    else
    {
      ok(0); # Not a unix endline as expected
    }
  }
}

# ---------------------------------------------------------------------------

