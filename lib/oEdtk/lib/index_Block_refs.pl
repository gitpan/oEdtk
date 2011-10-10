#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config 		qw(config_read);
use oEdtk::DBAdmin 		qw(db_connect);
use oEdtk::Outmngr 	0.07	qw(omgr_stats);
use Term::ReadKey;
use Sys::Hostname;
	

if (@ARGV < 2) {
	&usage();
}

my ($event, $idldoc, $idseqpg) = ($ARGV[0], $ARGV[1], $ARGV[2]);
if 		($event=~/^ANO$/i) {
} elsif 	($event=~/^DUPLE$/i){
} elsif 	($event=~/^STOP$/i){
} elsif 	($event=~/^RESET$/i){
} else {
	&usage();
}

if 		($idldoc!~/^\d{16}$/i) { # 1392153206001881
	&usage();
}
$idseqpg = $idseqpg || 0;

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_DSN_STATS',
    { AutoCommit => 1, RaiseError => 1 });




################################################################################

my $sql = "select ED_REFIDDOC, ED_SOURCE, ED_IDLDOC, ED_SEQDOC, ED_DTEDTION, ED_NOMDEST"
		. " from edtk_index "
		. " where ed_IDLDOC = ? " ;
	$sql .=  "  and ed_idseqpg  = ? " if ($idseqpg > 0);
	$sql .=  "  group by ED_REFIDDOC, ED_IDLDOC, ED_SEQDOC, ED_NOMDEST, ED_DTEDTION, ED_SOURCE ";
	$sql .=  "  order by ED_REFIDDOC, ED_IDLDOC, ED_SEQDOC, ED_NOMDEST, ED_DTEDTION, ED_SOURCE ";

	my @values;
	push (@values, $idldoc);
	push (@values, $idseqpg) if ($idseqpg > 0);
	my $sth = $dbh->prepare($sql);
	$sth->execute(@values);

	my $rows= $sth->fetchall_arrayref();

if ($#$rows<0) {
	warn "INFO : pas de donnees associees.\n";
	exit;
}


my $row_count= $#$rows + 1;
if ($row_count<=10) {
	foreach my $row (@$rows) {
		printf "%14s  %6s %16s %09d %8s %-30s \n", @$row, ""; # 1391152325098839
	}
}
print "WARN : Confirm Block request to set ". $row_count ." doc(s) for '$event' event ? (y/n)\n";

ReadMode('raw');
my $key = ReadKey();
if 		($key!~/^y$/i) {
	die "WARN : abort request\n";
}
ReadMode ('restore');

	$sql = "INSERT INTO EDTK_TRACKING(ED_TSTAMP, ED_USER, ED_SEQ, ED_SNGL_ID, ED_APP, ED_JOB_EVT, ED_OBJ_COUNT, ED_CORP, ED_HOST, ED_K4_VAL) ";
	$sql .=" VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
	my $trk = $dbh->prepare($sql);
# revoir le tracking : mettre un vrai timestamp, la bonne ed_app
$trk->execute('20111003111111', 'idx_Block', $idseqpg, $idldoc, 'idx_Block', 'W', $row_count , $cfg->{'EDTK_CORP'}, hostname(),  "$event for @values");


my 	$updt = "UPDATE EDTK_INDEX SET ED_DTLOT = ?, ED_SEQLOT = ?, ED_DTPOSTE = ? WHERE ED_IDLDOC = ? ";
	# probleme la ligne suivante ne gère pas toutes les pages d'un même doc
	$updt .=" AND ED_IDSEQPG  = ? " if ($idseqpg > 0);
	$sth = $dbh->prepare($updt);

# rajouter un controle, on a pas le droit de changer l'etat d'un doc déjà loti
# mais on a le droit de faire un reset pour rejouer le lotissement
if ($event!~/^RESET$/i) {
	$sth->execute($event, $event, $event, @values);
} else {
	my $NULL="";
	$sth->execute($NULL, $NULL, @values);
}
print "DONE ";
################################################################################

sub usage () {
	die "Usage: $0 <ANO|DUPLE|STOP|RESET> <idldoc|seqlot> [idseqpg] \n\n\t ANO\tblock doc(s) for anomaly in doc\n\t DUPLE\tblock duplicated doc(s)\n\t STOP\tblock to stop doc(s)\n\t RESET\tunblock to redo doc(s)\n";
	# ajouter gestion du cas RESET d'un seqlot complet
}

1;