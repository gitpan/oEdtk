#!/usr/bin/perl
use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect tracking_table_create);

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DBI_DSN');

tracking_table_create($dbh, $cfg->{'EDTK_DBI_TRACKING'}, $cfg->{'EDTK_MAX_USER_KEY'});
