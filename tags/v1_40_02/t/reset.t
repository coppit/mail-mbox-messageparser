#!/usr/bin/perl

# Test that we can reset a file midway through parsing.

use strict;

use Test::More;
use lib 't';
use Mail::Mbox::MessageParser;
use Mail::Mbox::MessageParser::Config;
use File::Spec::Functions qw(:ALL);
use Test::Utils;
use FileHandle;

eval 'require Storable;';

my @files = <t/mailboxes/*.txt>;
@files = grep { $_ ne 't/mailboxes/vm-emacs.txt' } @files;

mkdir catfile('t','temp'), 0700;

plan (tests => 6 * scalar (@files));

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  print "Testing partial mailbox reset with Perl implementation\n";
  TestPartialRead($filename,0,0);

  SKIP:
  {
    print "Testing partial mailbox reset with Cache implementation\n";

    skip('Storable not installed',1) unless defined $Storable::VERSION;

    InitializeCache($filename);

    TestPartialRead($filename,1,0);
  }

  SKIP:
  {
    print "Testing partial mailbox reset with Grep implementation\n";

    skip('GNU grep not available',1)
      unless defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'};

    TestPartialRead($filename,0,1);
  }

  print "Testing full mailbox reset with Perl implementation\n";
  TestFullRead($filename,0,0);

  SKIP:
  {
    print "Testing full mailbox reset with Cache implementation\n";

    skip('Storable not installed',1) unless defined $Storable::VERSION;

    TestFullRead($filename,1,0);
  }

  SKIP:
  {
    print "Testing full mailbox reset with Grep implementation\n";

    skip('GNU grep not available',1)
      unless defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'};

    TestFullRead($filename,0,1);
  }
}

# ---------------------------------------------------------------------------

sub TestPartialRead
{
  my $filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s#\.t##;

  my ($folder_name) = $filename =~ /\/([^\/\\]*)\.txt$/;

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
    catfile('t','results',"${testname}_${folder_name}.stdout");

  CheckDiffs([$compare_filename,$output_filename]);
}

# ---------------------------------------------------------------------------

sub TestFullRead
{
  my $filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s#\.t##;

  my ($folder_name) = $filename =~ /\/([^\/\\]*)\.txt$/;

  my $output_filename =
    catfile('t','temp',"${testname}_${folder_name}_${enable_cache}_${enable_grep}.stdout");

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
    catfile('t','results',"${testname}_${folder_name}.stdout");

  CheckDiffs([$compare_filename,$output_filename]);
}

# ---------------------------------------------------------------------------

