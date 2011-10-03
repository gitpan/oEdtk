#!/usr/bin/env perl

use strict;
use warnings;

use oEdtk::EDMS qw(EDMS_process_zip);

if (@ARGV < 2) {
	die "Usage: $0 <ged.zip> <outdir>\n";
}

EDMS_process_zip($ARGV[0], $ARGV[1]);
