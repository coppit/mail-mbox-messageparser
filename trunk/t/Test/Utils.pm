package Test::Utils;

use strict;
use Exporter;
use Test::More;
use Text::Diff;
use FileHandle::Unget;
use File::Spec::Functions qw(:ALL);

use vars qw( @EXPORT @ISA );
use Mail::Mbox::MessageParser;

@ISA = qw( Exporter );
@EXPORT = qw( CheckDiffs InitializeCache ModuleInstalled
  Broken_Pipe No_such_file_or_directory
);

# ---------------------------------------------------------------------------

sub CheckDiffs
{
  my @pairs = @_;

  local $Test::Builder::Level = 2;

  foreach my $pair (@pairs)
  {
    my $filename = $pair->[0];
    my $output_filename = $pair->[1];

    print "Comparing $output_filename to $filename\n";

    my @diffs;
    diff $output_filename, $filename, { STYLE => 'OldStyle', OUTPUT => \@diffs };

    my $numdiffs = grep { /^\d+[cd]\d+$/ } @diffs;

    if ($numdiffs != 0)
    {
      open DIFF_OUTPUT, ">$output_filename.diff";
      print DIFF_OUTPUT "diff \"$output_filename\" \"$filename\"\n";
      print DIFF_OUTPUT @diffs;
      close DIFF_OUTPUT;

      print "Failed, with $numdiffs differences.\n";
      print "  See $output_filename.diff.\n";
      ok(0,"Computing differences between $filename and $output_filename");
      return;
    }
    else
    {
      print "Output $output_filename looks good.\n";

      unlink $output_filename;
    }
  }

  ok(1,"Computing differences");
}

# ---------------------------------------------------------------------------

sub InitializeCache
{
  my $filename = shift;

  my $cache_file = catfile('t','temp','cache');

  Mail::Mbox::MessageParser::SETUP_CACHE({'file_name' => $cache_file});
  Mail::Mbox::MessageParser::CLEAR_CACHE();

  my $filehandle = new FileHandle::Unget($filename);

  my $folder_reader =
      new Mail::Mbox::MessageParser( {
        'file_name' => $filename,
        'file_handle' => $filehandle,
        'enable_cache' => 1,
        'enable_grep' => 0,
      } );

  die $folder_reader unless ref $folder_reader;

  my $prologue = $folder_reader->prologue;

  # This is the main loop. It's executed once for each email
  while(!$folder_reader->end_of_file())
  {
    $folder_reader->read_next_email();
  }

  $filehandle->close();

  Mail::Mbox::MessageParser::WRITE_CACHE();
}

# ---------------------------------------------------------------------------

sub ModuleInstalled
{
  my $module_name = shift;

  $module_name =~ s#::#/#g;
  $module_name .= '.pm';

  foreach my $inc (@INC)
  {
    return 1 if -e catfile($inc,$module_name);
  }

  return 0;
}

# ---------------------------------------------------------------------------

sub No_such_file_or_directory
{
  my $filename = 0;

  $filename++ while -e $filename;

  local $!;

  my $foo = new FileHandle;
  $foo->open($filename);

  die q{Couldn't determine local text for "No such file or directory"}
    if $! eq '';

  return $!;
}

# ---------------------------------------------------------------------------

# I think this works, but I haven't been able to test it because I can't find
# a system which will report a broken pipe. Also, is there a pure Perl way of
# doing this?
sub Broken_Pipe
{
  mkdir catdir('t','temp'), 0700;

  my $script_path = catfile('t','temp','broken_pipe.pl');
  my $dev_null = devnull();

  open F, ">$script_path";
  print F<<EOF;
unless (open B, '-|')
{
  open(F, "|cat 2>$dev_null");
  print F 'x';
  close F;
  exit;
}
EOF
  close F;

  my $result = `$^X $script_path 2>&1 1>$dev_null`;

  $result = '' unless defined $result;

  return $result;
}

# ---------------------------------------------------------------------------

1;
