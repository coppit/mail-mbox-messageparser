#!/usr/bin/perl
# use perl                                  -*- mode: Perl; -*-

use strict;
use ExtUtils::MakeMaker;

require 5.004;

@ARGV = Set_Install_Options(@ARGV)
  unless (grep {/^PREFIX=/} @ARGV) || (grep {/^INSTALLDIRS=/} @ARGV);

my %makefile_attributes = Compute_Makefile_Attributes(@ARGV);

WriteMakefile( %makefile_attributes );

# --------------------------------------------------------------------------

sub Set_Install_Options
{
  my @args = @_;

  my $install_location = ExtUtils::MakeMaker::prompt(
    "Choose your installation type:\n[1] normal Perl locations\n" .
    "[2] custom locations\n=>" => '1');

  if ($install_location eq '2')
  {
    my $home = Get_Home_Directory();

    print "\n","-"x78,"\n\n";

    my $prefix = ExtUtils::MakeMaker::prompt(
      "What PREFIX should I use?\n=>" => $home);

    push @args,"PREFIX=$prefix";
  }

  return @args;
}

# --------------------------------------------------------------------------

# Figures out the user's home directory in Unix

sub Get_Home_Directory()
{
  # Get the user's home directory. First try the password info, then the
  # registry (if it's a Windows machine), then any HOME environment variable.
  my $home = eval { (getpwuid($>))[7] } || $ENV{HOME};

  die <<"  EOF"
Your home directory could not be determined. I tried to get your
home directory using both getpwuid and your HOME environment variable.
  EOF
    unless defined $home;

  return $home;
}

# --------------------------------------------------------------------------

sub Compute_Makefile_Attributes
{
  my @args = @_;

  my %makefile_attributes = (
    'NAME'  => 'Mail::Mbox::MessageParser',
    'VERSION_FROM' => 'lib/Mail/Mbox/MessageParser.pm',
    'PM' => {
      'lib/Mail/Mbox/MessageParser.pm' =>
        '$(INST_LIB)/Mail/Mbox/MessageParser.pm',
      'lib/Mail/Mbox/MessageParser/Grep.pm' =>
        '$(INST_LIB)/Mail/Mbox/MessageParser/Grep.pm',
      'lib/Mail/Mbox/MessageParser/Cache.pm' =>
        '$(INST_LIB)/Mail/Mbox/MessageParser/Cache.pm',
      'lib/Mail/Mbox/MessageParser/Perl.pm' =>
        '$(INST_LIB)/Mail/Mbox/MessageParser/Perl.pm',
    },

    'dist'  => { COMPRESS => 'gzip -9', SUFFIX => 'gz' },
    'clean' => { FILES => 't/temp' },
    'PREREQ_PM' => { 'Storable' => 0 },
    'DIR' => [ ],
  );

  return %makefile_attributes;
}

# --------------------------------------------------------------------------

# So that "SUPER" works right
package MY;

sub test {
  my $inherited = shift->SUPER::test(@_);
  $inherited =~ s#testdb ::#testdb :: copy_test_modules#;
  $inherited =~ s#test ::#test :: copy_test_modules#;
  $inherited;
}

sub postamble
{
# Add a target for testing the speed, and one for testing
# functionality
'
copy_test_modules: $(TO_INST_PM)
	@$(PERLRUNINST) "-MExtUtils::Install" \
	-e "pm_to_blib({qw{lib/Test/CompareFiles.pm $(INST_LIB)/Test/CompareFiles.pm}},\'$(INST_LIB)/auto\',\'$(PM_FILTER)\')"

testspeed :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) "-I$(INST_LIB)" \
	  "-I$(INST_ARCHLIB)" t/speed.pl

testfunc :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) "-I$(INST_LIB)" \
	  "-I$(INST_ARCHLIB)" t/*.t
';
}

