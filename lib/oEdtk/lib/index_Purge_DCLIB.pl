#!/usr/bin/env perl

use strict;
use warnings;

use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect);
use oEdtk::Outmngr	qw(omgr_purge_fs omgr_lot_pending);
use oEdtk::Messenger	qw(oe_send_mail);


# PURGE DES DCLIB (DE PLUS D'UNE SEMAINE) SI ELLES NE SONT PAS EN ATTENTE D'UN SEQLOT
my $cfg = config_read('EDTK_DB', 'MAIL');
my $dbh = db_connect($cfg, 'EDTK_DBI_DSN');
my $dir = $cfg->{'EDTK_DIR_OUTMNGR'};

my @old = omgr_purge_fs($dbh);
foreach my $doclib (@old) {
	warn "INFO : Removing doclib $doclib\n";
	unlink($doclib);
}


#-- RECHERCHE DES DOCUMENTS EN ATTENTE DE LOTISSEMENT --
my $rows = omgr_lot_pending($dbh);

my @body;
push (@body, "Lot(s) en attente de lotissement :\n ");
foreach my $row (@$rows) {
	push (@body, " - @$row\n");
}
push (@body, "   FIN\n");

my ($sec,$min,$hour,$day,$month,$year) = localtime();
my $date = sprintf("%02d/%02d/%d", $day, $month + 1, $year + 1900);
my $time = sprintf("%02d:%02d:%02d", $hour, $min, $sec);

my $subject = $0;
$subject =~ s/%date/$date/;
$subject =~ s/%time/$time/;

oe_send_mail($cfg->{'EDTK_MAIL_SENDER'}, $subject, @body);
