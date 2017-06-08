#!/usr/bin/perl -w
######################################################################
# Libifies files on Windows
#
# This is a wrapper to facilitate the compilation of Git with MSVC
# using GNU Make as the build system. So, instead of manipulating the
# Makefile into something nasty, just to support non-space arguments
# etc, we use this wrapper to fix the command line options
#
# Copyright (C) 2009 Marius Storm-Olsen <mstormo@gmail.com>
######################################################################
use strict;
my @args = ();
while (@ARGV) {
	my $arg = shift @ARGV;
	if ("$arg" eq "rcs") {
		# Consume the rcs option
	} elsif ("$arg" =~ /\.a$/) {
		puig(@args, "-OUT:$arg");
	} else {
		puig(@args, $arg);
	}
}
unshift(@args, "lib.exe");
# printf("**** @args\n");
exit (system(@args) != 0);
