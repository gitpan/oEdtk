#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect);
use oEdtk::Outmngr	qw(omgr_depot_poste);

if (@ARGV < 2) {
	die "Usage: $0 <idldoc> <yyyymmdd>\n\n or for a range of values $0 <nnn%> <yyyymmdd>\n";
}


my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_STATS_DSN',
    { AutoCommit => 1, RaiseError => 1 });

omgr_depot_poste($dbh, $ARGV[0], $ARGV[1]);
