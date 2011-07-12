#!/usr/bin/perl
use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config  qw(config_read);
use oEdtk::DBAdmin qw(db_connect
		      params_FILIERES_table_create
		      params_LOTS_table_create
		      params_REFIDDOC_table_create
		      params_SUPPORTS_table_create
		   );

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_PARAM_DSN');

params_FILIERES_table_create($dbh);
params_LOTS_table_create($dbh);
params_REFIDDOC_table_create($dbh);
params_SUPPORTS_table_create($dbh);
