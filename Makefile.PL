#!/usr/bin/perl
# use perl                                  -*- mode: Perl; -*-

use strict;
use ExtUtils::MakeMaker;
use lib 'lib';
use Config;
use File::Spec;

require 5.004;

my @program_options = grep {/^(DIFF|GREP|TZIP|GZIP|BZIP2?)=/} @ARGV;
@ARGV = grep {!/^(DIFF|GREP|TZIP|GZIP|BZIP2?)=/} @ARGV;

unless ((grep {/^PREFIX=/} @ARGV) || (grep {/^INSTALLDIRS=/} @ARGV))
{
  @ARGV = Set_Install_Options(@ARGV);
}

print "\n","-"x78,"\n\n";

my %makefile_attributes = Compute_Makefile_Attributes();

WriteMakefile( %makefile_attributes );

print "\n","-"x78,"\n\n";

Configure(@program_options);

exit;

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

sub Compute_Makefile_Attributes
{
  my %makefile_attributes = (
    'NAME'  => 'Mail::Mbox::MessageParser',
    'VERSION_FROM' => 'lib/Mail/Mbox/MessageParser.pm',
    'dist'  => {
      COMPRESS => 'gzip -9',
      SUFFIX => 'gz',
      PREOP => q{$(CP) t/mailboxes/*\ * $(DISTVNAME)/t/mailboxes; $(CP) t/results/*\ * $(DISTVNAME)/t/results},
    },

    'clean' => { FILES => 't/temp' },
    'PM' => {
      'lib/Mail/Mbox/MessageParser.pm' => '$(INST_LIB)/Mail/Mbox/MessageParser.pm',
      'lib/Mail/Mbox/MessageParser/Cache.pm' => '$(INST_LIB)/Mail/Mbox/MessageParser/Cache.pm',
      'lib/Mail/Mbox/MessageParser/Grep.pm' => '$(INST_LIB)/Mail/Mbox/MessageParser/Grep.pm',
      'lib/Mail/Mbox/MessageParser/Perl.pm' => '$(INST_LIB)/Mail/Mbox/MessageParser/Perl.pm',
    },
    'PREREQ_PM' => { 'Storable' => 0, 'IO::String' => 0 },
    'DIR' => [ ],
  );

  return %makefile_attributes;
}

# --------------------------------------------------------------------------

sub Configure
{
  my @args = @_;

  my %locations = Get_Program_Locations(@args);

  Update_Code('lib/Mail/Mbox/MessageParser.pm', \%locations);
  Update_Code('lib/Test/Utils.pm', \%locations);
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

sub Get_Program_Locations
{
  my @args = @_;

  my %defaults = (
      'diff'     => 'diff',
      'grep'     => 'grep',
      'tzip'     => 'tzip',
      'gzip'     => 'gzip',
      'bzip2'    => 'bzip2',
      'bzip'     => 'bzip2',
  );

  my %programs = (
      'diff'     => undef,
      'grep'     => undef,
      'tzip'     => undef,
      'gzip'     => undef,
      'bzip2'    => undef,
      'bzip'     => undef,
  );

  foreach my $arg (@args)
  {
    my ($var,$value) = $arg =~ /^(.*?)=(.*)$/;
    $value = undef if $value eq '';
    $programs{'diff'} = $value if $var eq 'DIFF';
    $programs{'grep'} = $value if $var eq 'GREP';
    $programs{'tzip'} = $value if $var eq 'TZIP';
    $programs{'bzip'} = $value if $var eq 'BZIP';
    $programs{'gzip'} = $value if $var eq 'GZIP';
    $programs{'bzip2'} = $value if $var eq 'BZIP2';
  }

  return %programs if grep {/^(DIFF|GREP|TZIP|GZIP|BZIP2?)=/} @args;

  print<<EOF;
You must now specify the location of external programs for decompressing
compressed folders. You must specify the full path--otherwise you may
accidentally execute a trojan version of the decompression program.  You can
enter "none" to disable support for decompressing files of a given type.

EOF

  my @path = split /$Config{path_sep}/, $ENV{PATH};

  foreach my $program (sort keys %programs)
  {
    my $name = $Config{$program} || $defaults{$program};

    my $full_path = Find_Program($name, [@path]);
    $full_path = $name if !defined $full_path && MM->maybe_command($name);

    $full_path = 'none' if !defined $full_path || $full_path eq '';

    my $choice = ExtUtils::MakeMaker::prompt(
      "Where can I find your \"$program\" executable?" => $full_path);

    $programs{$program} = undef, next if $choice eq 'none';

    if (File::Spec->file_name_is_absolute($choice) &&
      MM->maybe_command($choice))
    {
      $programs{$program} = $choice;
      next;
    }
    else
    {
      print "\"$choice\" does not appear to be a valid executable\n";
      redo;
    }
  }

  return %programs;
}

# --------------------------------------------------------------------------

sub Find_Program
{
  my $program = shift;
  my @path = @{ shift @_ };

  my $param = (($program =~ s/(\s+.*)//) ? $1 : '');

  for my $dir (@path)
  {
    my $abs = File::Spec->catfile($dir, $program);
    return $abs.$param if $abs = MM->maybe_command($abs);
  }

  return undef;
}

# ---------------------------------------------------------------------------

# Figures out the user's home directory in Unix

sub Get_Home_Directory
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

# So that "SUPER" works right
package MY;

sub postamble
{
'
testspeed :: pure_all
	PERL_DL_NONLAZY=1 $(PERLRUN) "-I$(INST_LIB)" \
	  "-I$(INST_ARCHLIB)" t/speed.pl
';
}

