#!/usr/bin/perl -w
#
#  fat-set-uuid.pl - Set the UUID and/or LABEL of a FAT16/FAT32 filesystem
#
#  Usage:
#    fat-set-uuid.pl [-l label] [-u uuid] device
#
#  Copyright © 2010, Nick Andrew <nick@nick-andrew.net>
#  License: GPL Version 3+, http://gplv3.fsf.org/

use strict;

use Getopt::Std qw(getopts);
use IO::File qw(O_RDONLY O_RDWR);

use vars qw($opt_l $opt_u);

getopts('l:u:');

my $device = shift @ARGV;

if ($opt_l) {
	if ($opt_l !~ /^[a-zA-Z0-9-]{1,11}$/) {
		die "Invalid label $opt_l";
	}
}

if ($opt_u) {
	if ($opt_u !~ /^[0-9a-fA-F]{4}-[0-9a-fA-F]{4}$/) {
		die "Invalid uuid $opt_u - need XXXX-XXXX";
	}
}

if (! $device) {
	die "Usage: fat-set-uuid.pl [-l label] [-u uuid] device";
}

if (! $opt_l && ! $opt_u) {
	listLabel($device);
}
else {
	updateLabel($device, $opt_l, $opt_u);
	listLabel($device);
}

exit(0);

# ---------------------------------------------------------------------------
# Check for a 'FAT' marker at the specified location
# ---------------------------------------------------------------------------

sub findInfo {
	my ($fh, $type_o) = @_;

	# First look for the type
	seek($fh, $type_o, 0);
	my $type;
	my $n = sysread($fh, $type, 5);
	if ($n != 5) {
		die "No type\n";
	}

	if ($type !~ /FAT(\d+)/) {
		return 0;
	}

	return 1;
}

# ---------------------------------------------------------------------------
# Print the filesystem information at the specified location. Make it usable by
# a shell script.
# ---------------------------------------------------------------------------

sub printInfo {
	my ($fh, $type, $uuid_o) = @_;

	print "TYPE=$type\n";

	seek($fh, $uuid_o, 0);
	my $buf;
	my $n = sysread($fh, $buf, 15);
	if ($n != 15) {
		die "No uuid/label\n";
	}

	my ($a,$b,$c,$d) = unpack('H2H2H2H2', substr($buf, 0, 4));
	my $uuid=uc("$d$c-$b$a");
	print "UUID=$uuid\n";

	my $label = substr($buf, 4, 11);
	$label =~ s/  *$//;
	print "LABEL=$label\n";
}

# ---------------------------------------------------------------------------
# Set the UUID and/or filesystem label at a specified file offset
# ---------------------------------------------------------------------------

sub setLabel {
	my ($fh, $offset, $label, $uuid) = @_;

	if ($uuid) {
		if ($uuid !~ /^(..)(..)-(..)(..)$/) {
			die "Invalid uuid $uuid\n";
		}

		my $s = pack('H2H2H2H2', $4, $3, $2, $1);
		seek($fh, $offset, 0);
		syswrite($fh, $s);
	}

	if ($label) {
		# Space-pad label out to 11 characters
		$label = sprintf("%-11.11s", $label);
		seek($fh, $offset + 4, 0);
		syswrite($fh, $label);
	}
}

# ---------------------------------------------------------------------------
# Find which FAT filesystem type the device is, if possible, and print
# other filesystem information.
# ---------------------------------------------------------------------------

sub listLabel {
	my ($device) = @_;

	my $fh = IO::File->new($device, O_RDONLY());
	if (! $fh) {
		die "Unable to open $device for read - $!";
	}

	if (findInfo($fh, 0x36)) {
		printInfo($fh, "FAT16", 0x27);
	}
	elsif (findInfo($fh, 0x52)) {
		printInfo($fh, "FAT32", 0x43);
	}
	else {
		print "TYPE=unknown\n";
	}
}

sub updateLabel {
	my ($device, $label, $uuid) = @_;

	my $fh = IO::File->new($device, O_RDWR());
	if (! $fh) {
		die "Unable to open $device for write - $!";
	}

	if (findInfo($fh, 0x36)) {
		setLabel($fh, 0x27, $label, $uuid);
	}
	elsif (findInfo($fh, 0x52)) {
		setLabel($fh, 0x43, $label, $uuid);

		if (findInfo($fh, 0xc52)) {
			setLabel($fh, 0xc43, $label, $uuid);
		}
	}
}
