#!/usr/bin/perl

# Test that we can pipe compressed data to the module

use strict;

use File::Temp qw(tempfile);
use Test::More;
use lib 't';
use File::Spec::Functions qw(:ALL);
use Test::Utils;
use Mail::Mbox::MessageParser::Config;
use FileHandle;
use File::Slurper qw(read_binary write_binary);

my @files = <t/mailboxes/*.txt.*>;
@files = grep { !/non-mailbox/ && !/malformed/ } @files;

plan (tests => 1 * scalar (@files));

my $test_program = do { local $/; <DATA> };

foreach my $filename (@files) 
{
  print "Testing filename: $filename\n";

  SKIP:
  {
    skip('bzip2 not available',1)
      if $filename =~ /\.bz2$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'bzip2'};

    skip('bzip not available',1)
      if $filename =~ /\.bz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'bzip'};

    skip('lzip not available',1)
      if $filename =~ /\.lz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'lzip'};

    skip('xz not available',1)
      if $filename =~ /\.xz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'xz'};

    skip('gzip not available',1)
      if $filename =~ /\.gz$/ &&
        !defined $Mail::Mbox::MessageParser::Config{'programs'}{'gzip'};

    TestImplementation($filename, $test_program);
  }
}

# ---------------------------------------------------------------------------

sub TestImplementation
{
  my $filename = shift;
  my $test_program = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s/\.t//;

  my ($folder_name) = $filename =~ /\/([^\/\\]*)\.txt.*$/;

  my ($output_fh, $output_fn) = tempfile();
  binmode $output_fh;
  my ($script_fh, $script_fn) = tempfile();

  local $/ = undef;

  write_binary($script_fn, $test_program);

  my $mailbox = read_binary($filename);

  open PIPE, "|$^X -I" . catdir('blib','lib') . " $script_fn \"$output_fn\"";
  binmode PIPE;
  local $SIG{PIPE} = sub { die "test program pipe broke" };
  print PIPE $mailbox;
  close PIPE;

  $filename =~ s#\.(tz|bz2|lz|xz|gz)$##;

  CheckDiffs([$filename,$output_fn]);
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
  binmode $output_file_handle;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => undef,
        'file_handle' => $file_handle,
        'enable_cache' => 0,
        'enable_grep' => 0,
        'debug' => $ENV{TEST_VERBOSE},
      } );

  die $folder_reader unless ref $folder_reader;

  print $output_file_handle $folder_reader->prologue();

  while (!$folder_reader->end_of_file())
  {
    my $email_text = $folder_reader->read_next_email();
    print $output_file_handle $$email_text;
  }

  close $output_file_handle;
}

################################################################################
