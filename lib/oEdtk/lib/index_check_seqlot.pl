#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect);
use oEdtk::Outmngr	qw(omgr_check_seqlot_ref);

if (@ARGV < 1) {
	die "Usage: $0 <seqlot>\n\n check references for seqlot\n";
}

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_STATS_DSN',
    { AutoCommit => 1, RaiseError => 1 });

my $rows = omgr_check_seqlot_ref($dbh, $ARGV[0]);

if ($#$rows<0) {
	print "INFO : pas de donnees asociees.\n";
	exit;
}

foreach my $row (@$rows) {
	print("INFO : @$row \n");
}
