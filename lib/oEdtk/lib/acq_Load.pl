#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config 		qw(config_read);
use oEdtk::DBAdmin 		qw(db_connect);
use oEdtk::Outmngr 		qw(csv_import);

if (@ARGV < 1) {
	die "Usage: $0 <acq.csv>\n";
}

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DBI_DSN',
    { AutoCommit => 1, RaiseError => 1 });

csv_import($dbh, "EDTK_ACQ", $ARGV[0]);

1;