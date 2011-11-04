#!/usr/bin/perl
use oEdtk::trackEdtk qw (prepare_Tracking_Env edit_Track_Table);

prepare_Tracking_Env();

print "Looking for DBI_DNS $ENV{EDTK_DBI_DSN}...\n";
my $sql_request = $ARGV[0];
edit_Track_Table($sql_request);
1;