#!/usr/bin/perl

# These tests operate on a mail archive I found on the web at
# http://el.www.media.mit.edu/groups/el/projects/handy-board/mailarc.txt
# and then broke into pieces

# Any differences between the expected (timeresults/test#.real) and actual
# (timeresults/test#.out) outputs are stored in test#.diff in the current
# directory.

use strict;
use warnings 'all';

use Benchmark qw( timethis cmpthese );
use FileHandle;

my $TIME_ITERATIONS = 3;
my $MAILBOX_SIZE = 1_000_000;
my $TEMP_MAILBOX = 't/temp/bigmailbox.txt';

mkdir 't/temp';

CreateInputFile($TEMP_MAILBOX);

my $data = CollectData($TEMP_MAILBOX);

print "=========================================\n";

DoHeadToHeadComparison($data);

print "=========================================\n";

DoImplementationsComparison($data);

# make clean will take care of it
#END
#{
#  RemoveInputFile($TEMP_MAILBOX);
#}

################################################################################

sub RemoveInputFile
{
  my $filename = shift;

  unlink $filename;
}

################################################################################

sub CreateInputFile
{
  my $filename = shift;

  return
    if -e $filename && abs((-s $filename) - $MAILBOX_SIZE) <= 200_000;

  print "Making input file.\n";

  my $data;

  open FILE, 't/mailboxes/mailarc-1.txt';
  local $/ = undef;
  $data = <FILE>;
  close FILE;

  open FILE, ">$filename";

  while (-s $filename < $MAILBOX_SIZE)
  {
    print FILE $data;
  }

  close FILE;
}

################################################################################

sub CollectData
{
  my $filename = shift;

  print "Collecting data...\n\n";

  local $/ = undef;

  open TESTER, ">t/temp/test_speed.pl";
  my $test_program = <DATA>;
  $test_program =~ s/\$TIME_ITERATIONS/$TIME_ITERATIONS/eg;
  print TESTER $test_program;
  close TESTER;

  # Warm the OS file cache
  open MAILBOX, $filename;
  <MAILBOX>;
  close MAILBOX;

  my ($new_data, $old_data);

  {
    use IPC::Open3;
    use Symbol qw(gensym);
    my $pid = open3(gensym, ">&STDOUT", \*RESULTS, "$^X t/temp/test_speed.pl lib");
    my $results = <RESULTS>;
    waitpid($pid, 0);
    close RESULTS;

    die $results unless $results =~ /VAR1/;

    $results =~ s/VAR1/new_data/;
    eval $results;
  }

  {
    use IPC::Open3;
    use Symbol qw(gensym);
    my $pid = open3(gensym, ">&STDOUT", \*RESULTS, "$^X t/temp/test_speed.pl old");
    my $results = <RESULTS>;
    waitpid($pid, 0);
    close RESULTS;

    die $results unless $results =~ /VAR1/;

    $results =~ s/VAR1/old_data/;
    eval $results;
  }

  my %merged_data = (%$old_data, %$new_data);

  return \%merged_data;
}

################################################################################

sub DoHeadToHeadComparison
{
  my $data = shift;

  print "HEAD TO HEAD COMPARISON\n\n";

  my %simple = ('Old Simple' => $data->{'Old Simple'},
    'New Simple' => $data->{'New Simple'});
  Benchmark::cmpthese(\%simple);

  print "-----------------------------------------\n";

  my %grep = ('Old Grep' => $data->{'Old Grep'},
    'New Grep' => $data->{'New Grep'});
  Benchmark::cmpthese(\%grep);

  print "-----------------------------------------\n";

  my %cache_init = ('Old Cache Init' => $data->{'Old Cache Init'},
    'New Cache Init' => $data->{'New Cache Init'});
  Benchmark::cmpthese(\%cache_init);

  print "-----------------------------------------\n";

  my %cache_use = ('Old Cache Use' => $data->{'Old Cache Use'},
    'New Cache Use' => $data->{'New Cache Use'});
  Benchmark::cmpthese(\%cache_use);
}
################################################################################

sub DoImplementationsComparison
{
  my $data = shift;

  print "IMPLEMENTATION COMPARISON\n\n";

  my %old = (
    'Old Simple' => $data->{'Old Simple'},
    'Old Grep' => $data->{'Old Grep'},
    'Old Cache Init' => $data->{'Old Cache Init'},
    'Old Cache Use' => $data->{'Old Cache Use'},
    );
  Benchmark::cmpthese(\%old);

  print "-----------------------------------------\n";

  my %new = (
    'New Simple' => $data->{'New Simple'},
    'New Grep' => $data->{'New Grep'},
    'New Cache Init' => $data->{'New Cache Init'},
    'New Cache Use' => $data->{'New Cache Use'},
    );
  Benchmark::cmpthese(\%new);
}

################################################################################

__DATA__

use strict;
use Benchmark qw( timethis cmpthese );
use FileHandle;

die unless @ARGV == 1;

my $modpath = shift @ARGV;
my $filename = 't/temp/bigmailbox.txt';

my %data;

unshift @INC, $modpath;
require Mail::Mbox::MessageParser;

my $label = $modpath eq 'old' ? 'Old' : 'New';

$data{"$label Simple"} =
  timethis(-$TIME_ITERATIONS, sub { ParseFile($filename,0,0) }, "    $label Simple");
$data{"$label Grep"} =
  timethis(-$TIME_ITERATIONS, sub { ParseFile($filename,1,0) }, "      $label Grep");
$data{"$label Cache Init"} =
  timethis(-$TIME_ITERATIONS, sub { InitializeCache($filename) }, "$label Cache Init");
$data{"$label Cache Use"} =
  timethis(-$TIME_ITERATIONS, sub { ParseFile($filename,0,1) }, " $label Cache Use");

use Data::Dumper;
print STDERR Dumper \%data;

exit;

################################################################################

sub InitializeCache
{
  my $filename = shift;

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => 't/temp/cache'});
  Mail::Mbox::MessageParser::CLEAR_CACHE();

  my $filehandle = new FileHandle($filename);

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $filehandle,
        'enable_cache' => 1,
        'enable_grep' => 0,
      } );

  my $prologue = $folder_reader->prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    $folder_reader->read_next_email();
  }

  Mail::Mbox::MessageParser::WRITE_CACHE();
}

################################################################################

sub ParseFile
{
  my $filename = shift;
  my $enable_grep = shift;
  my $enable_cache = shift;

  my $file_handle = new FileHandle;
  $file_handle->open($filename) or die $!;

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => 't/temp/cache'})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $file_handle,
        'enable_cache' => $enable_cache,
        'enable_grep' => $enable_grep,
      } );

  while (!$folder_reader->{end_of_file})
  {
    my $email_text = $folder_reader->read_next_email();
  }

  close $file_handle;
}

################################################################################
