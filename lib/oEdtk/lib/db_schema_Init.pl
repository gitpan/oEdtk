#!/usr/bin/perl
use strict;
use warnings;

use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect schema_create);

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DBI_DSN');

schema_create($dbh, $cfg->{'EDTK_DBI_TRACKING'},
    $cfg->{'EDTK_MAX_USER_KEY'});
