#!/usr/bin/perl

use lib 'lib';
use Mail::Mbox::MessageParser;

my $string = "From maor  Sun Jun  1 01:40:55 1997\nRecieved\n";

open IN, 'mbox';
#binmode IN;
local $/ = undef;
my $text = <IN>;
close IN;

#while ($text =~ m/\n\n/mg) {
#  print pos($text) . "\n";
#}
#
#exit;

die unless @ARGV;

my $file_name = $ARGV[0];

my $folder_reader =
  new Mail::Mbox::MessageParser( {
    'file_name' => $file_name,
    'enable_cache' => 0,
    'enable_grep' => 0,
    'debug' => 1,
  } );

die $folder_reader unless ref $folder_reader;

# Any newlines or such before the start of the first email
my $prologue = $folder_reader->prologue;
print $prologue;

# This is the main loop. It's executed once for each email
while(!$folder_reader->end_of_file())
{
  print "#######################\n";
  my $email = $folder_reader->read_next_email();
  print $$email;
}
