#!/usr/bin/perl

use strict;
use warnings;

use oEdtk::Main;
use oEdtk::Config 		qw(config_read);
use oEdtk::DBAdmin 		qw(db_connect);
use oEdtk::Outmngr 	0.07	qw(omgr_stats);
#use Text::CSV;

if (@ARGV < 1) {
	die "Usage: $0 <today|week|week_value|ALL> [refiddoc] [seqlot|source|source_name]\n"
		."\t week_value : number of a week in the year\n\t source_name: job name in tracking\n\n"
		." check references for tracked sources\n";
}

my $period=	$ARGV[0] || "today";
my $refiddoc=	$ARGV[1] || 0;
my $lot	= 	$ARGV[2] || 0;

my $cfg = config_read('EDTK_STATS');
my $dbh = db_connect($cfg, 'EDTK_DSN_STATS',
    { AutoCommit => 1, RaiseError => 1 });




################################################################################

use Date::Calc		qw(Today Gmtime Week_of_Year);
	my $time = time;
	my ($year,$month,$day, $hour,$min,$sec, $doy,$dow,$dst) =
		Gmtime($time);
	my ($week,) = Week_of_Year($year,$month,$day);
	my ($idldocKey, $select, $sql, $groupby, $orderby, @sql_values);

	if ($period =~ /^today$/i) {
		$idldocKey = sprintf ("%1d%02d%1d", $year % 10, $week, $dow );
		
	} elsif ($period =~ /^all$/i){
		
	} elsif ($period =~ /^(\d{1,2})$/){
		$idldocKey = sprintf("%1d%02d", $year % 10, $1 );

	} elsif ($period =~ /^week$/i){
		$idldocKey = sprintf("%1d%02d", $year % 10, $week );

	} else { 
		$idldocKey = sprintf("%1d%02d", $year % 10, $week );
	}
	$idldocKey .="%"; # étrangement pour les cas week et \d2 on a le message suivant si on met % dans le sprintf : Invalid conversion in sprintf: end of string at C:\Sources\edtk_MNT\lib\index_Check_docs_omgr.pl line 44. 
	push (@sql_values, $idldocKey);


	$select	= "SELECT COUNT (DISTINCT A.ED_IDLDOC||TO_CHAR(A.ED_SEQDOC,'FM0000000')) AS NB_DOCS, A.ED_REFIDDOC, A.ED_IDLDOC "; 
	$sql		= " FROM " . $cfg->{'EDTK_STATS_OUTMNGR'} . " A, " . $cfg->{'EDTK_STATS_TRACKING'} . " B "
				. " WHERE A.ED_IDLDOC=B.ED_SNGL_ID AND B.ED_JOB_EVT='J' AND  A.ED_IDLDOC LIKE ? ";
#				. " WHERE A.ED_IDLDOC=B.ED_SNGL_ID AND B.ED_JOB_EVT='J' AND A.ED_SEQLOT != 'ANO' AND A.ED_SEQLOT LIKE ? ";
	$groupby  = " GROUP BY A.ED_REFIDDOC, A.ED_IDLDOC ";
	$orderby	= " ORDER BY A.ED_REFIDDOC, A.ED_IDLDOC ";

	my $col = "";
	if 		($refiddoc) { 
		$sql .= " AND ED_REFIDDOC = ? ";
		push (@sql_values, $refiddoc);
	}

	if		($lot eq "seqlot") { 
		$select	.=", A.ED_SEQLOT ";
		$groupby 	.=", A.ED_SEQLOT ";
		$orderby	= ", A.ED_SEQLOT ";
		$col = uc ($lot);

	} elsif	($lot eq "source") { 
		$select	.=", B.ED_SOURCE ";
		$groupby 	.=", B.ED_SOURCE ";
		$orderby	= ", B.ED_SOURCE ";
		$col = uc ($lot);
	
	} elsif 	($lot) {
		$select	.=", B.ED_SOURCE ";
		$sql		.="  AND B.ED_SOURCE = ? ";
		$groupby 	.=", B.ED_SOURCE ";
		$orderby	= ", B.ED_SOURCE ";
		push (@sql_values, $lot);
	}

	$sql = $select . $sql . $groupby . $orderby;
	my $sth = $dbh->prepare($sql);
	$sth->execute(@sql_values);

	my $rows= $sth->fetchall_arrayref();
	warn sprintf "INFO : %6s %-15s %-16s %s  from EDTK_STATS_OUTMNGR\n", "NB_DOCS", "REFIDDOC", "IDLDOC", $col;

################################################################################


if ($#$rows<0) {
	warn "INFO : pas de donnees associees.\n";
	exit;
}

foreach my $row (@$rows) {
		for (my $i=0; $i<=$#$row ; $i++){
			$$row[$i] = $$row[$i] || ""; # CERTAINES VALEURS PEUVENT NE PAS ÊTRE RENSEIGNÉES DANS CERTAINS CAS	
		}
	printf "%14d %-15s %16s %s \n", @$row, ""; # 1391152325098839
}
