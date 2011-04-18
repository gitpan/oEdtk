#!/usr/bin/perl

use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect table_move);
use warnings;
use strict;

if (@ARGV < 2) {
	die "Usage: $0 table_source table_cible [-create]\n";
}


my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DBI_DSN');

print "INFO : data from $ARGV[0] will be inserted in $ARGV[1]\n";

table_move($dbh, $ARGV[0], $ARGV[1], $ARGV[2]);

print "INFO : insert done into $ARGV[1]\n";
