#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config 		qw(config_read);
use oEdtk::DBAdmin 		qw(db_connect csv_import);


if (@ARGV < 1) {
	die "Usage: $0 <acq.csv>\n";
}

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DSN_DBI',
    { AutoCommit => 1, RaiseError => 1 });

csv_import($dbh, "EDTK_ACQ", $ARGV[0], 
			{ mode => 'merge', 
			header => 'ED_SEQLOT,ED_LOTNAME,ED_DTPRINT,ED_DTPOST,ED_NBPGLOT,ED_NBPLISLOT,ED_DTPOST2' }
			);

1;