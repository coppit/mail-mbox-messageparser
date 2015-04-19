#!/usr/bin/perl

use strict;

# For PRIVATE Module::Install extensions
use lib 'private-lib';

use inc::Module::Install;
use File::Slurp;

# To prevent MakeMaker from processing our old directory
BEGIN { makemaker_args( NORECURS => 1 ) }

all_from('lib/Mail/Mbox/MessageParser.pm');

auto_set_bugtracker;
githubmeta;

configure_requires(
  'File::Slurp' => 0,
);

requires(
  'FileHandle::Unget' => 0,
  'Storable' => 0,
);

test_requires(
  'File::Slurp' => 0,
  'Test::More' => 0,
  'Text::Diff' => 0,
  'File::Path' => 2.08,
);

check_optional( 'Benchmark::Timer' => '0.7100',
  "Install Benchmark::Timer if you want to run \"make testspeed\"\n");

Add_Test_Target('testspeed', 't/speed.pl');

Configure_Programs();

license 'gpl2';
auto_license(holder => 'David Coppit');

enable_verbose_cpan_testing();

WriteAll();

{
  print "Fixing POD in inc/Sort/Versions.pm\n";

  my $code = read_file('inc/Sort/Versions.pm');
  $code =~ s|^=encoding.*||m;
  write_file('inc/Sort/Versions.pm', $code);
}

{
  print "Fixing PREOP in the Makefile to copy files with spaces during building\n";

  my $code = read_file('Makefile');

  my $commands = q{; $(CP) t/mailboxes/*\\ * $(DISTVNAME)/t/mailboxes; $(CP) t/results/*\\ * $(DISTVNAME)/t/results};
  $code =~ s|^(PREOP\s*=.*)|$1$commands|m;

  write_file('Makefile', $code);
}

exit;

# --------------------------------------------------------------------------

sub Configure_Programs
{
  my %info = (
      'diff'     => { default => 'diff', argname => 'DIFF' },
      'grep'     => { default => 'grep', argname => 'GREP',
                      types => {
                        'GNU' => { fetch => \&get_gnu_version,
                                   numbers => '[2.1,)', },
                      },
                    },
      'lzip'     => { default => 'lzip', argname => 'LZIP',
                      types => {
                        'GNU' => { fetch => \&get_gnu_version,
                                   numbers => '[1.3,)', },
                      },
                    },
      'xz'       => { default => 'xz', argname => 'XZ' },
      'gzip'     => { default => 'gzip', argname => 'GZIP' },
      'bzip'     => { default => 'bzip2', argname => 'BZIP',
                      types => {
                        'bzip2' => { fetch => \&get_bzip2_version,
                                     numbers => '[1.0,)', },
                      },
                    },
      'bzip2'    => { default => 'bzip2', argname => 'BZIP2',
                      types => {
                        'bzip2' => { fetch => \&get_bzip2_version,
                                     numbers => '[1.0,)', },
                      },
                    },
  );

	# XXX: disable grep support by pretending like the user doesn't have grep
	# installed
	delete $info{'grep'};

  my %locations = get_program_locations(\%info);

  # XXX: pretend we didn't find grep
  $locations{'grep'} = {
		'version' => undef, 'type' => undef, 'path' => undef
	};

  Update_Config('lib/Mail/Mbox/MessageParser/Config.pm', \%locations);
  Update_Config('old/Mail/Mbox/MessageParser/Config.pm', \%locations)
    if -e 'old/Mail/Mbox/MessageParser.pm';
}

# --------------------------------------------------------------------------

sub Update_Config
{
  my $filename = shift;
  my %locations = %{ shift @_ };

  my $code = read_file($filename);

  foreach my $program (keys %locations)
  {
    if (defined $locations{$program}{'path'})
    {
      $locations{$program}{'path'} = "\'$locations{$program}{'path'}\'";
    }
    else
    {
      $locations{$program}{'path'} = "undef";
    }
  }

  if ($code =~ /'programs'\s*=>\s*{\s*?\n([^}]+?) *}/s)
  {
    my $original_programs = $1;
    my $new_programs = '';

    foreach my $program (sort keys %locations)
    {
      $new_programs .= "    '$program' => $locations{$program}{'path'},\n";
    }

    $code =~ s/\Q$original_programs\E/$new_programs/;
  }
  else
  {
    die "Couldn't find programs hash in $filename";
  }

  write_file($filename, $code);
}
