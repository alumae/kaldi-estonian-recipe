#! /usr/bin/perl
use strict;

#print "Files are: @ARGV[0]\n";
#print "Weigts are: @ARGV[1]\n";

my @files = split(/\s+/, @ARGV[0]);

my $weights = @ARGV[1];
#print "-- $weights\n";
$weights =~ s/.*\((.*)\).*/\1/g;
#print "-- $weights\n";
my @wlist = split(/ /, $weights);

for (0 .. $#files) {
	my $lm = $files[$_];
	$lm =~ s/\.ppl/\.bin-lm/;
	
	if ($_ == 0) {
		print "-lm  " . $lm . " -lambda  " . $wlist[$_];
	} else {
		my $i = "";
		if ($_ > 1) {
			$i = $_;
		}
		print " -mix-lm" . $i . " " . $lm . " -mix-lambda" . $i . " " . $wlist[$_];
	}
}
print "\n";
