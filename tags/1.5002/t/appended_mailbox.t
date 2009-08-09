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

mkdir catfile('t','temp'), 0700;

plan (tests => 6 );

my $source_filename = 't/mailboxes/mailarc-1.txt';
my $mailbox_filename = 't/temp/tempmailbox';

{
	print "Testing modified mailbox with Perl implementation\n";

	InitializeMailbox1($source_filename,$mailbox_filename);

	TestModifiedMailbox($source_filename,$mailbox_filename,0,0,
		GetSecondPart1($source_filename));
}

SKIP:
{
	print "Testing modified mailbox with Cache implementation\n";

	skip('Storable not installed',1) unless defined $Storable::VERSION;

	InitializeMailbox1($source_filename,$mailbox_filename);

	InitializeCache($mailbox_filename);

	TestModifiedMailbox($source_filename,$mailbox_filename,1,0,
		GetSecondPart1($source_filename));
}

SKIP:
{
	print "Testing modified mailbox with Grep implementation\n";

	skip('GNU grep not available',1)
		unless defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'};

	InitializeMailbox1($source_filename,$mailbox_filename);

	TestModifiedMailbox($source_filename,$mailbox_filename,0,1,
		GetSecondPart1($source_filename));
}

{
	print "Testing modified mailbox with Perl implementation\n";

	InitializeMailbox2($source_filename,$mailbox_filename);

	TestModifiedMailbox($source_filename,$mailbox_filename,0,0,
		GetSecondPart2($source_filename));
}

SKIP:
{
	print "Testing modified mailbox with Cache implementation\n";

	skip('Storable not installed',1) unless defined $Storable::VERSION;

	InitializeMailbox2($source_filename,$mailbox_filename);

	InitializeCache($mailbox_filename);

	TestModifiedMailbox($source_filename,$mailbox_filename,1,0,
		GetSecondPart2($source_filename));
}

SKIP:
{
	print "Testing modified mailbox with Grep implementation\n";

	skip('GNU grep not available',1)
		unless defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'};

	InitializeMailbox2($source_filename,$mailbox_filename);

	TestModifiedMailbox($source_filename,$mailbox_filename,0,1,
		GetSecondPart2($source_filename));
}

# ---------------------------------------------------------------------------

sub InitializeMailbox1
{
  my $source_filename = shift;
  my $mailbox_filename = shift;

	open SOURCE, $source_filename;
	local $/ = undef;
	my $mail = <SOURCE>;
	close SOURCE;

	my ($firstpart) = $mail =~ /(.*)From .*/s;

	open MAILBOX, ">$mailbox_filename";
	print MAILBOX $firstpart;
	close MAILBOX;
}

# ---------------------------------------------------------------------------

sub InitializeMailbox2
{
  my $source_filename = shift;
  my $mailbox_filename = shift;

	open SOURCE, $source_filename;
	local $/ = undef;
	my $mail = <SOURCE>;
	close SOURCE;

	my ($firstpart) = $mail =~ /(..*?)From .*/s;

	open MAILBOX, ">$mailbox_filename";
	print MAILBOX $firstpart;
	close MAILBOX;
}

# ---------------------------------------------------------------------------

sub TestModifiedMailbox
{
  my $source_filename = shift;
  my $mailbox_filename = shift;
  my $enable_cache = shift;
  my $enable_grep = shift;
	my $second_part = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s/\.t//;

  my ($folder_name) = $source_filename =~ /\/([^\/\\]*)\.txt$/;

  my $output_filename = catfile('t','temp',
    "${testname}_${folder_name}_${enable_cache}_${enable_grep}.stdout");

  my $output = new FileHandle(">$output_filename");
  binmode $output;

  my $filehandle = new FileHandle($mailbox_filename);

  my $cache_file = catfile('t','temp','cache');

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => $cache_file})
    if $enable_cache;

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $mailbox_filename,
        'file_handle' => $filehandle,
        'enable_cache' => $enable_cache,
        'enable_grep' => $enable_grep,
      } );

  die $folder_reader unless ref $folder_reader;

  print $output $folder_reader->prologue;

  # Read just 1 email
  print $output ${$folder_reader->read_next_email()};

	AppendToMailbox($mailbox_filename, $second_part);

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    print $output ${ $folder_reader->read_next_email() };
  }

  $output->close();

  CheckDiffs([$source_filename,$output_filename]);
}

# ---------------------------------------------------------------------------

sub GetSecondPart1
{
  my $source_filename = shift;

	open SOURCE, $source_filename;
	local $/ = undef;
	my $mail = <SOURCE>;
	close SOURCE;

	my ($secondpart) = $mail =~ /.*(From .*)/s;

	return $secondpart;
}

# ---------------------------------------------------------------------------

sub GetSecondPart2
{
  my $source_filename = shift;

	open SOURCE, $source_filename;
	local $/ = undef;
	my $mail = <SOURCE>;
	close SOURCE;

	my ($secondpart) = $mail =~ /..*?(From .*)/s;

	return $secondpart;
}

# ---------------------------------------------------------------------------

sub AppendToMailbox
{
  my $mailbox_filename = shift;
  my $email = shift;

	open MAILBOX, ">>$mailbox_filename";
	print MAILBOX $email;
	close MAILBOX;
}
