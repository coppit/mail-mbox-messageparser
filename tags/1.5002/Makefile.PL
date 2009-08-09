#!/usr/bin/perl

use strict;

use inc::Module::Install;

all_from          ('lib/Mail/Mbox/MessageParser.pm');

build_requires    (
                    'Test::More' => 0,
                    'Text::Diff' => 0,
                  );

requires          (
                    'Storable' => 0,
                    'FileHandle::Unget' => 0,
                  );

check_optional  ( 'Benchmark::Timer' => '0.7100',
  "Install Benchmark::Timer if you want to run \"make speedtest\"\n");

sub MY::postamble {
  return &Module::AutoInstall::postamble . <<'EOF';
testspeed :: pure_all
	PERL_DL_NONLAZY=1 $(PERLRUN) "-I$(INST_LIB)" \
	  "-I$(INST_ARCHLIB)" t/speed.pl
EOF
}

clean_files       ('t/temp');

# Module::Install doesn't figure out that Module::Install::CheckOptional needs
# this. Include it manually.
include           (
                    'Module::AutoInstall' => 0,
                  );

Configure_Programs();

WriteAll();

Fix_PREOP();

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

  my $code = _Read_Code($filename);

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

  _Write_Code($filename, $code);
}

# --------------------------------------------------------------------------

sub _Read_Code
{
  my $filename = shift;

  local $/ = undef;

  open SOURCE, $filename
    or die "Couldn't open file \"$filename\": $!";
  my $code = <SOURCE>;
  close SOURCE;

  return $code;
}

# --------------------------------------------------------------------------

sub _Write_Code
{
  my $filename = shift;
  my $code = shift;

  open SOURCE, ">$filename"
    or die "Couldn't open grepmail file \"$filename\": $!";
  print SOURCE $code;
  close SOURCE;
}

# --------------------------------------------------------------------------

sub Fix_PREOP
{
  print "Fixing PREOP in the Makefile to copy files with spaces during building\n";

  my $commands = q{; $(CP) t/mailboxes/*\\ * $(DISTVNAME)/t/mailboxes; $(CP) t/results/*\\ * $(DISTVNAME)/t/results};

	my $makefile_code;
	{
		local $/ = undef;
		open IN, 'Makefile';
		$makefile_code = <IN>;
		close IN;
	}

  $makefile_code =~ s|^(PREOP\s*=.*)|$1$commands|m;

	open OUT, '>Makefile';
	print OUT $makefile_code;
	close OUT;
}
