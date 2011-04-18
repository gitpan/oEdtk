#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect);
use oEdtk::Outmngr	qw(omgr_purge_db);

if (@ARGV < 1) {
	die "Usage: $0 <sngl_id|seqlot>\n\n Supression d'un lot de document (sng_id) OU d'un lot de mise sous pli (seqlot) \n";
}

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_STATS_DSN',
    { AutoCommit => 1, RaiseError => 1 });

omgr_purge_db($dbh, $ARGV[0]);
