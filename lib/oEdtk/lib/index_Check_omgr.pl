#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect);
use oEdtk::Outmngr	qw(omgr_check_seqlot_ref);

if (@ARGV < 1) {
	die "Usage: $0 <seqlot_ref|idldoc_ref>\n\n look statitics for checked docs in output manager\n";
}

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_DSN_STATS',
    { AutoCommit => 1, RaiseError => 1 });

my $rows = omgr_check_seqlot_ref($dbh, $ARGV[0]);


if ($#$rows<0) {
	warn "INFO : pas de donnees associees.\n";
	exit;
}

foreach my $row (@$rows) {
		for (my $i=0; $i<=$#$row ; $i++){
			$$row[$i] = $$row[$i] || ""; # CERTAINES VALEURS PEUVENT NE PAS ÊTRE RENSEIGNÉES DANS CERTAINS CAS	
		}
	printf "%14s %-16s %16s %9d %-7s %9s %10s\n", @$row, ""; # 1391152325098839
}

