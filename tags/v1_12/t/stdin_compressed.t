#!/usr/bin/perl

# Test that we can pipe compressed data to the module

use strict;

use Test;
use lib 'lib';
use File::Spec::Functions qw(:ALL);
use Test::Utils;
use FileHandle;

my @files = <t/mailboxes/*.txt.*>;
@files = grep { !/non-mailbox/ } @files;

mkdir catfile('t','temp'), 0700;

plan (tests => 1 * scalar (@files));

local $/ = undef;

my $test_program = <DATA>;

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

  TestImplementation($filename, $test_program);
}

# ---------------------------------------------------------------------------

sub TestImplementation
{
  my $filename = shift;
  my $test_program = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s#\.t##;

  my ($folder_name) = $filename =~ /\/([^\/\\]*)\.txt.*$/;

  my $output_filename = catfile('t','temp',
    "${testname}_${folder_name}.stdout");

  local $/ = undef;

  open TESTER, ">" . catfile('t','temp','stdin.pl');
  print TESTER $test_program;
  close TESTER;

  open MAILBOX, $filename;
  my $mailbox = <MAILBOX>;
  close MAILBOX;

  open PIPE, "|$^X -I" . catdir('blib','lib') . " " .
    catfile('t','temp','stdin.pl') . " \"$output_filename\"";
  binmode PIPE;
  local $SIG{PIPE} = sub { die "test program pipe broke" };
  print PIPE $mailbox;
  close PIPE;

  $filename =~ s#\.(tz|bz2|gz)$##;

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
  binmode $output_file_handle;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => undef,
        'file_handle' => $file_handle,
        'enable_cache' => 0,
        'enable_grep' => 0,
      } );

  die $folder_reader unless ref $folder_reader;

  print $output_file_handle $folder_reader->prologue();

  while (!$folder_reader->{end_of_file})
  {
    my $email_text = $folder_reader->read_next_email();
    print $output_file_handle $$email_text;
  }

  close $output_file_handle;
}

################################################################################
