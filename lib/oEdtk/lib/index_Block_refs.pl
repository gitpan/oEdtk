#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config 		qw(config_read);
use oEdtk::DBAdmin 		qw(db_connect);
use oEdtk::Outmngr 	0.28	qw(omgr_stats);
use Term::ReadKey;
use Sys::Hostname;


sub usage () {
	warn "Usage: $0 <ANO|DUPLE|STOP|RESET> <idldoc|seqlot> [idseqpg|STOP_status] \n\n"
		."\tThis changes docs status for omgr administration.\n\n"
		."\t ANO\tblock doc(s) for anomaly in doc\n"
		."\t DUPLE\tblock duplicated doc(s)\n"
		."\t STOP\tblock to stop doc(s)\t(index_Purge_DCLIB won't delete DCLIB)\n"
		."\t RESET\tunblock to redo doc(s)\t(index_Purge_DCLIB won't delete DCLIB)\n";
	exit 1;
}
	

if (@ARGV < 2 or $ARGV[0] =~/-h/i) {
	&usage();
}

my ($event, $key1, $key2) = ($ARGV[0], $ARGV[1], $ARGV[2]);
if 		($event=~/^ANO$/i) {
} elsif 	($event=~/^DUPLE$/i){
} elsif 	($event=~/^STOP$/i){
} elsif 	($event=~/^RESET$/i){
} else {
	&usage();
}

my $type="";
if 		($key1=~/^\d{16}$/){ # 1392153206001881
		$type = 'idldoc';

} elsif 	($key1=~/^\d{7}$/) { # 1411123
		$type = 'seqlot';

} else {
	&usage();
}
$key2 = $key2 || 0;

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_DBI_STATS',
    { AutoCommit => 1, RaiseError => 1 });




################################################################################

my @values;
push (@values, $key1);
my $sql = "SELECT ED_REFIDDOC, ED_SOURCE, ED_IDLDOC, ED_SEQDOC, ED_DTEDTION, ED_NOMDEST"
		. " FROM EDTK_INDEX ";

if 	($type eq 'idldoc') {
	$sql.= " WHERE ED_IDLDOC = ? ";
	if (defined $key2 && ($key2=~/^STOP$/) ){
		$sql .="  AND ED_SEQLOT  = ? ";
		push (@values, $key2);

	} elsif (defined $key2 && $key2 > 0 ){
		$sql .="  AND ED_SEQDOC  = (SELECT ED_SEQDOC FROM EDTK_INDEX WHERE ED_IDLDOC = ? AND ED_IDSEQPG = ? )";
		push (@values, $key1, $key2);
	}

} elsif ($type eq 'seqlot'){
	$sql.= " WHERE ED_SEQLOT = ? ";
}
	$sql .=" GROUP BY ED_REFIDDOC, ED_IDLDOC, ED_SEQDOC, ED_NOMDEST, ED_DTEDTION, ED_SOURCE ";
	$sql .=" ORDER BY ED_REFIDDOC, ED_IDLDOC, ED_SEQDOC, ED_NOMDEST, ED_DTEDTION, ED_SOURCE ";


my $sth = $dbh->prepare($sql);
$sth->execute(@values);
my $rows= $sth->fetchall_arrayref();

if ($#$rows<0) {
	warn "INFO : pas de donnees associees.\n";
	# tracker l'action
	exit;
}


my $row_count= $#$rows + 1;
if ($row_count<=10) {
	foreach my $row (@$rows) {
		printf "%14s  %6s %16s %09d %8s %-30s \n", @$row, ""; # 1391152325098839
	}
}
warn "INFO : Confirm Block request to set ". $row_count ." doc(s) for '$event' event ? (y/n)\n";

ReadMode('raw');
my $key = ReadKey();
if 		($key!~/^y$/i) {
	die "INFO : abort request\n";
}
ReadMode ('restore');


my 	$updt = "UPDATE EDTK_INDEX SET ED_DTLOT = ?, ED_SEQLOT = ?, ED_DTPOSTE = ?, ED_STATUS = ? ";
my	$sequence= 0;
if 	($type eq 'idldoc') {
	$updt.= " WHERE ED_IDLDOC = ? ";

	if (defined $key2 && ($key2=~/^STOP$/) ){
		$updt .="  AND ED_SEQLOT  = ? ";
		
	} elsif (defined $key2 && $key2 > 0){
		$updt .="  AND ED_SEQDOC  = (SELECT ED_SEQDOC FROM EDTK_INDEX WHERE ED_IDLDOC = ? AND ED_IDSEQPG = ? )";
		$sequence = $key2;
	}

} elsif ($type eq 'seqlot'){
	$updt.= " WHERE ED_SEQLOT = ? ";
}
	$sth = $dbh->prepare($updt);


# rajouter un controle, on a pas le droit de changer l'etat d'un doc d�j� loti
# mais on a le droit de faire un reset pour rejouer le lotissement
if ($event!~/^RESET$/i && $event!~/^STOP$/i) {
	# pour tous les autres event on ne rejoue pas les docs, ils seront purg�s (index_Purge_DCLIB)
	# warn "INFO : $updt \n $event, $event, $event, $event, @values\n";
	$sth->execute($event, $event, $event, $event, @values);

} else {
	my $NULL="";
	# warn "INFO : $updt \n $NULL, $NULL, $NULL, $event, @values\n";
	$sth->execute($NULL, $NULL, $NULL, $event, @values);
}


# REVOIR LE TRACKING : METTRE UN VRAI TIMESTAMP, LA BONNE ED_APP
$sql = "INSERT INTO EDTK_TRACKING(ED_TSTAMP, ED_USER, ED_SEQ, ED_SNGL_ID, ED_APP, ED_JOB_EVT, ED_OBJ_COUNT, ED_CORP, ED_HOST, ED_K4_VAL) ";
$sql .=" VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
my $trk = $dbh->prepare($sql);
$trk->execute('20111003111111', 'idx_Block', $sequence, $key1, 'idx_Block', 'W', $row_count , $cfg->{'EDTK_CORP'}, hostname(),  "$event for @values");

print "DONE ";
################################################################################

1;