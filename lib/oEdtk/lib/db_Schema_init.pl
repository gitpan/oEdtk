#!/usr/bin/perl
use strict;
use warnings;

use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect create_SCHEMA);

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DSN_DBI');

create_SCHEMA($dbh);
