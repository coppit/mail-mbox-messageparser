#!/usr/bin/perl

use strict;
use inc::Module::Install;
use lib 'inc';
use Module::Install::GetProgramLocations;

Check_Custom_Installation();

print "\n", '-'x78, "\n\n";

name            ('Mail-Mbox-MessageParser');
author          ('David Coppit <david@coppit.org>');
abstract_from   ('lib/Mail/Mbox/MessageParser.pm');
version_from    ('lib/Mail/Mbox/MessageParser.pm');
license         ('gpl');

requires        (
                  'Storable' => 0,
                  'FileHandle::Unget' => 0,
                );

skip            ( 'Test',);

# Optional features and their modules
features        (
                  'Speed Tests' => [
                    -default => 0,
                    recommends( 'Benchmark::Timer' => '0.60' ),
                  ],
                );

postamble       (
'
testspeed :: pure_all
	PERL_DL_NONLAZY=1 $(PERLRUN) "-I$(INST_LIB)" \
	  "-I$(INST_ARCHLIB)" t/speed.pl
'
);

include         ('ExtUtils/AutoInstall.pm');

clean_files     ('t/temp');

print "\n", '-'x78, "\n\n";

Configure_Programs();

print "\n", '-'x78, "\n\n";

auto_install    ( );
WriteAll();

Fix_PREOP();

exit;

# --------------------------------------------------------------------------

sub Configure_Programs
{
  my %info = (
      'diff'     => { default => 'diff', argname => 'DIFF' },
      'grep'     => { default => 'grep', argname => 'GREP',
                      versions => {
                        'GNU' => { fetch => \&Get_GNU_Grep_Version,
                                   numbers => '[2.1,)', },
                      },
                    },
      'tzip'     => { default => 'tzip', argname => 'TZIP' },
      'gzip'     => { default => 'gzip', argname => 'GZIP' },
      'bzip'     => { default => 'bzip2', argname => 'BZIP',
                      versions => {
                        'bzip2' => { fetch => \&Get_Bzip2_Version,
                                     numbers => '[1.0,)', },
                      },
                    },
      'bzip2'    => { default => 'bzip2', argname => 'BZIP2',
                      versions => {
                        'bzip2' => { fetch => \&Get_Bzip2_Version,
                                     numbers => '[1.0,)', },
                      },
                    },
  );

  my %locations = Get_Program_Locations(\%info);

  Update_Code('lib/Mail/Mbox/MessageParser.pm', \%locations);
  Update_Code('lib/Test/Utils.pm', \%locations);
  Update_Code('old/Mail/Mbox/MessageParser.pm', \%locations)
    if -e 'old/Mail/Mbox/MessageParser.pm';

  return %locations;
}

# --------------------------------------------------------------------------

sub Update_Code
{
  my $filename = shift;
  my %locations = %{ shift @_ };

  my $code = _Read_Code($filename);

  foreach my $program (keys %locations)
  {
    if (defined $locations{$program})
    {
      $locations{$program} = "\'$locations{$program}\'";
    }
    else
    {
      $locations{$program} = "undef";
    }
  }

  if ($code =~ /(PROGRAMS = \(.*?\))/s)
  {
    my $original_programs = $1;
    my $new_programs = $original_programs;

    $new_programs =~ s/('diff' *=> *).*?,/$1$locations{diff},/;
    $new_programs =~ s/('grep' *=> *).*?,/$1$locations{grep},/;
    $new_programs =~ s/('tzip' *=> *).*?,/$1$locations{tzip},/;
    $new_programs =~ s/('gzip' *=> *).*?,/$1$locations{gzip},/;
    $new_programs =~ s/('compress' *=> *).*?,/$1$locations{gzip},/;
    $new_programs =~ s/('bzip' *=> *).*?,/$1$locations{bzip},/;
    $new_programs =~ s/('bzip2' *=> *).*?,/$1$locations{bzip2},/;

    $code =~ s/\Q$original_programs\E/$new_programs/;
  }
  else
  {
    die "Couldn't find programs hash in MessageParser.pm";
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

  my $commands = q{; \$(CP) t/mailboxes/*\\\\ * \$(DISTVNAME)/t/mailboxes; \$(CP) t/results/*\\\\ * \$(DISTVNAME)/t/results};

  system "$^X -pi -e 's|^(PREOP\\s*=.*)|\$1$commands|' Makefile";
}
