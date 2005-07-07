#!/usr/bin/perl

use strict;

use Test::More;
use lib 't';
use Mail::Mbox::MessageParser::Config;
use File::Spec::Functions qw(:ALL);
use Test::Utils;

my $GREP = $Mail::Mbox::MessageParser::Config{'programs'}{'grep'} || 'grep';

my %tests = (
"$GREP --extended-regexp --line-number --byte-offset \"^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$\" " . catfile('t','mailboxes','mailarc-1.txt')
  => ['grep_1','none'],
"$GREP --extended-regexp --line-number --byte-offset \"^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$\" " . catfile('t','mailboxes','mailarc-2.txt')
  => ['grep_2','none'],
"$GREP --extended-regexp --line-number --byte-offset \"^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$\" " . catfile('t','mailboxes','mailarc-3.txt')
  => ['grep_3','none'],
"$GREP --extended-regexp --line-number --byte-offset \"^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$\" " . catfile('t','mailboxes','mailseparators.txt')
  => ['grep_4','none'],
);

my %expected_errors = (
);

mkdir catfile('t','temp'), 0700;

plan (tests => scalar (keys %tests));

my %skip = SetSkip(\%tests);

foreach my $test (sort keys %tests) 
{
  print "Running test:\n  $test\n";

  SKIP:
  {
    skip("$skip{$test}",1) if exists $skip{$test};

    TestIt($test, $tests{$test}, $expected_errors{$test});
  }
}

# ---------------------------------------------------------------------------

sub TestIt
{
  my $test = shift;
  my ($stdout_file,$stderr_file) = @{ shift @_ };
  my $error_expected = shift;

  my $testname = [splitdir($0)]->[-1];
  $testname =~ s#\.t##;

  my $test_stdout = catfile('t','temp',"${testname}_$stdout_file.stdout");
  my $test_stderr = catfile('t','temp',"${testname}_$stderr_file.stderr");

  system "$test 1>$test_stdout 2>$test_stderr";

  if (!$? && defined $error_expected)
  {
    print "Did not encounter an error executing the test when one was expected.\n\n";
    ok(0);
    return;
  }

  if ($? && !defined $error_expected)
  {
    print "Encountered an error executing the test when one was not expected.\n";
    print "See $test_stdout and $test_stderr.\n\n";
    ok(0);
    return;
  }


  my $real_stdout = catfile('t','results',$stdout_file);
  my $real_stderr = catfile('t','results',$stderr_file);

  CheckDiffs([$real_stdout,$test_stdout],[$real_stderr,$test_stderr]);
}

# ---------------------------------------------------------------------------

sub SetSkip
{
  my %tests = %{ shift @_ };

  my %skip;

  unless (defined $Mail::Mbox::MessageParser::Config{'programs'}{'grep'})
  {
    $skip{"$GREP --extended-regexp --line-number --byte-offset '^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$' " . catfile('t','mailboxes','mailarc-1.txt')}
    = 1;

    $skip{"$GREP --extended-regexp --line-number --byte-offset '^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$' " . catfile('t','mailboxes','mailarc-2.txt')}
    = 1;

    $skip{"$GREP --extended-regexp --line-number --byte-offset '^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$' " . catfile('t','mailboxes','mailarc-3.txt')}
    = 1;

    $skip{"$GREP --extended-regexp --line-number --byte-offset '^From [^:]+(:[0-9][0-9]){1,2} ([A-Z]{2,3} [0-9]{4}|[0-9]{4} [+-][0-9]{4}|[0-9]{4})( remote from .*)?\$' " . catfile('t','mailboxes','mailseparators.txt')}
    = 1;
  }

  return %skip;
}

# ---------------------------------------------------------------------------

