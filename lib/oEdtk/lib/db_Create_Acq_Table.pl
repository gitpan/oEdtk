#!/usr/bin/perl
use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config  qw(config_read);
use oEdtk::DBAdmin qw(db_connect
		      create_table_ACQUIT
		   );

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DSN_DBI');

create_table_ACQUIT($dbh);
