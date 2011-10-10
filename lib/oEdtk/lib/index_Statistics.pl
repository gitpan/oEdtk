#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config 		qw(config_read);
use oEdtk::DBAdmin 		qw(db_connect);
use oEdtk::Outmngr 	0.07	qw(omgr_stats);
use Text::CSV;

if (@ARGV < 1) {
	die "Usage: $0 <day|week|all|value> <idlot|idgplot> [file]\n\n \t where 'value' has the format wwd (one or more numbers like 521 or 52)\n";
}

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_DSN_STATS',
    { AutoCommit => 1, RaiseError => 1 });
my $pdbh = db_connect($cfg, 'EDTK_DSN_STATS');

my $rows = omgr_stats($dbh, $pdbh, $ARGV[0], $ARGV[1]||"idlot");
if ($#$rows<0) {
	warn "INFO : pas de statistiques pour cette periode.\n";
	exit;
}

my @cols;
if (defined($ARGV[1]) && $ARGV[1]!~/idlot/i) {
	@cols = ("LOT", "CORP", "PLIS", "DOCS", "FEUILLES", "PAGES", "FACES", "MODEDI ");
} else {
	@cols = ("LOT", "CORP", "ID_LOT", "PLIS", "DOCS", "FEUILLES", "PAGES", "FACES", "FIL.");
}

# If an output file was given on the command line, we dump the data in
# the given file in CSV format.
if (defined($ARGV[2]) && length($ARGV[2]) > 0) {
	open(my $fh, ">$ARGV[2]") or die $!;
	my $csv = Text::CSV->new({ binary => 1, eol => "\n" });
	$csv->print($fh, \@cols);
	foreach my $row (@$rows) {
		$csv->print($fh, $row);
	}
	close($fh);
	exit;
}

# Otherwise, we output in a human-readable way.
my $fmt = "%-16s%-8s" . "%9s" x (@cols - 3) . "  %-6s\n";
printf($fmt, @cols);
foreach my $row (@$rows) {
	printf($fmt, @$row);
}
