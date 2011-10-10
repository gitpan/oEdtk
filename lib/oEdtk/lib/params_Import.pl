#!/usr/bin/perl

use strict;
use warnings;

use Text::CSV;
use oEdtk::Main;
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect);

if ($#ARGV < 1) {
	die "Usage: $0 <table> <csv>\n";
	exit 1;
}

my ($table, $file) = @ARGV;

open(my $fh, "<", $file) or die "$file: $!\n";
my $csv = Text::CSV->new({ sep_char => ';', binary => 1 });

my $cfg = config_read('EDTK_DB');
my $dbh = db_connect($cfg, 'EDTK_DSN_PARAM',
    { AutoCommit => 0, RaiseError => 1 });

# Set the column names.
$csv->column_names($csv->getline($fh));

eval {
	if ($dbh->{'Driver'}->{'Name'} eq 'SQLite') {
		$dbh->do("DELETE FROM $table");
	} else {
		$dbh->do("TRUNCATE TABLE $table");
	}

	while (my $row = $csv->getline_hr($fh)) {
		my $sql = "INSERT INTO $table (" . join(', ', keys(%$row)) .
		    ") VALUES (" . join(', ', ('?') x keys(%$row)) . ")";
		$dbh->do($sql, undef, values(%$row));
	}
	$dbh->commit;
};
if ($@) {
	warn "ERROR: $@\n";
	eval { $dbh->rollback };
}

$dbh->disconnect;
close($fh);
