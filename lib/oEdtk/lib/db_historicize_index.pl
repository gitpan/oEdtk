#!/usr/bin/perl

use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect historicize_table);
use Term::ReadKey;
use POSIX		qw(strftime);
use warnings;
use strict;

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DBI_DSN');
my $wait_time =1;
my $suffixe =strftime "%Y%m%d%H%M%S", localtime;
$wait_time ||=500*$cfg->{'EDTK_WAITRUN'};

print "WARN : table should not be in use\n";
print "WARN : wait or press a key\n";

ReadMode('raw');
my $key = ReadKey($wait_time);
ReadMode ('restore');

historicize_table($dbh, $cfg->{'EDTK_DBI_OUTMNGR'}, $suffixe);

print "WARN : backup done for ".$cfg->{'EDTK_DBI_OUTMNGR'}."\n";
