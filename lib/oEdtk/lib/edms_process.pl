#!/usr/bin/env perl

use strict;
use warnings;

use oEdtk::EDM qw(edm_process_zip);

if (@ARGV < 2) {
	die "Usage: $0 <ged.zip> <outdir>\n";
}

edm_process_zip($ARGV[0], $ARGV[1]);
