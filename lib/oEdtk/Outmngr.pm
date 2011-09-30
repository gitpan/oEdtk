package oEdtk::Outmngr;

use strict;
use warnings;

use File::Basename;
use Text::CSV;
use Date::Calc		qw(Today Gmtime Week_of_Year);
use List::Util		qw(max sum);
use oEdtk::Config	qw(config_read);
use oEdtk::DBAdmin	qw(db_connect index_table_create @INDEX_COLS);
use POSIX			qw(strftime);
use DBI;
# use Sys::Hostname;

use Exporter;
our $VERSION	= 0.16;
our @ISA	= qw(Exporter);
our @EXPORT_OK	= qw(
			omgr_check_seqlot_ref 
			omgr_depot_poste 
			omgr_export 
			omgr_import 
			omgr_lot_pending
			omgr_purge_db 
			omgr_purge_fs
			omgr_referent_stats 
			omgr_stats 
		);

# Le lot par défaut.
use constant DEFLOT => 'DEF';
use constant DEFFIL => 'DEF';

# Description des traitements que l'on applique à nos lots de documents, avec
# la liste des champs mis à jour à chaque étape.
#
# 1. On insère chaque ligne de l'index dans la table $cfg->{'EDTK_DBI_OUTMNGR'} en renseignant
#    un certain nombre de champs supplémentaires, en utilisant les informations
#    tirées des tables EDTK_REFIDDOC et EDTK_SUPPORTS.
#      ED_PORTADR, ED_CATDOC, ED_REFIMP, ED_TYPED, ED_FORMATP, ED_PGORIEN,
#      ED_FORMDEF, ED_PAGEDEF, ED_FORMS, ED_NUMPGPLI
#
# 2. Une fois que toutes les lignes ont été insérées, on peut désormais faire
#    des calculs supplémentaires et enrichir à nouveau nos entrées.
#      ED_NBPGPLI, ED_NBPGDOC, ED_MODEDI
#
# 3. On peut maintenant sélectionner un lot pour nos documents.  On essaye
#    chacun des lots séquentiellement, dans l'ordre de priorité défini dans la
#    table EDTK_LOTS.  Si le lot matche des entrées, on assigne ces entrées au
#    lot correspondant.
#      ED_IDLOT
#
# 4. Une fois qu'un lot a été assigné, on en déduit un manufacturier via la
#    table EDTK_LOTS.  En fonction de ce manufacturier, on sélectionne une liste
#    de filières de production possibles, dans l'ordre de priorité défini dans la
#    table EDTK_FILIERES.  Comme pour l'étape 3, on essaye de matcher nos entrées
#    avec chacune de ces filières, en fonction de leurs contraintes.
#      ED_IDFILIERE
#
# 5. La filière de production ayant été déterminée, on sait si l'on va imprimer
#    en recto-verso ou juste en recto; on peut donc calculer de nouveaux champs
#    supplémentaires.
#      ED_PDSPLI, ED_NBFPLI
#
# 6. On peut finalement exporter nos entrées pour créer nos lots finaux à envoyer
#    au manufacturier.  Pour cela, on sélectionne les couples (idlot,idfilière)
#    uniques dans notre table $cfg->{'EDTK_DBI_OUTMNGR'}, et pour chacun de ces couples, on essaye
#    de satisfaire les contraintes en nombre de plis/pages minimum et maximum.  Si
#    c'est possible, on assigne un numéro de lot d'envoi unique aux documents.
#      ED_SEQLOT

# Read and process an index file, storing it in the database, while computing some values.
sub omgr_import($$$) {
	my ($app, $in, $corp) = @_;

	# Retrieve the database connection parameters.
	my $cfg = config_read('EDTK_DB');
	
	my $pdbh= db_connect($cfg, 'EDTK_PARAM_DSN');
	my $dbh = db_connect($cfg, 'EDTK_DBI_DSN', { AutoCommit => 0, RaiseError => 1 });

	# Create the $cfg->{'EDTK_DBI_OUTMNGR'} table if we're using SQLite.
	if ($dbh->{'Driver'}->{'Name'} eq 'SQLite') {
		index_table_create($dbh, $cfg->{'EDTK_DBI_OUTMNGR'});
	}

	eval {
		my ($idldoc, $numencs, $encpds) = omgr_insert($dbh, $pdbh, $app, $in, $corp);
		omgr_lot($dbh, $pdbh, $idldoc);
		omgr_filiere($dbh, $pdbh, $app, $idldoc, $numencs, $encpds);
		$dbh->commit;
	};
	if ($@) {
		warn "ERROR: $@\n";
		eval { $dbh->rollback };
	}

	$dbh->disconnect;
	$pdbh->disconnect;
}


sub omgr_insert($$$$$) {
	# - injection des données page/page de l'index compo en base de données
	# - complétion de l'index avec les infos des tables de paramétrage REFIDDOC et SUPPORTS
	# - calculs des quantités pages/supports
	# revoir la gestion des encarts   xxxxxxxxxx
	my ($dbh, $pdbh, $app, $in, $corp) = @_;
	my $cfg = config_read('EDTK_DB');

	# Récupération des paramètres de l'application documentaire.
	my $doc = $pdbh->selectrow_hashref("SELECT * FROM EDTK_REFIDDOC WHERE ED_REFIDDOC = ? " .
	    "AND (ED_CORP = ? OR ED_CORP = '%')", undef, $app, $corp);
	die $pdbh->errstr if $pdbh->err;
	if (!defined($doc)) {
		die "Could not find document \"$app\" in EDTK_REFIDDOC\n";
	}

	# Récupération du support pour la première page et les suivantes.
	my $p1 = $pdbh->selectrow_hashref('SELECT * FROM EDTK_SUPPORTS WHERE ED_REFIMP = ?',
	    undef, $doc->{'ED_REFIMP_P1'});
	die $pdbh->errstr if $pdbh->err;
	if (!defined($p1)) {
		die "Could not find support \"$doc->{'ED_REFIMP_P1'}\" in EDTK_SUPPORTS\n";
	}

	my $ps = $pdbh->selectrow_hashref('SELECT * FROM EDTK_SUPPORTS WHERE ED_REFIMP = ?',
	    undef, $doc->{'ED_REFIMP_PS'});
	die $pdbh->errstr if $pdbh->err;
	if (!defined($ps)) {
		die "Could not find support \"$doc->{'ED_REFIMP_PS'}\" in EDTK_SUPPORTS\n";
	}


	# Récupération de la liste des encarts à joindre pour ce document,
	# et en déduire le poids supplémentaire à ajouter à chaque pli
	my @encrefs = split(/,/, $doc->{'ED_REFIMP_REFIDDOC'} || "");
	my $now = strftime("%Y%m%d", localtime());
	my $sth = $pdbh->prepare('SELECT * FROM EDTK_SUPPORTS WHERE ED_REFIMP = ?')
	    or die $pdbh->errstr;
	my $encpds = 0;
	my @needed = ();
	foreach my $encref (@encrefs) {
	
		# l'erreur est ici : on devrait ajouter des ligens d'index par encart avec TYPIMP = E xxxxxx
		 
		my $enc = $pdbh->selectrow_hashref($sth, undef, $encref) or die $pdbh->errstr;
		if (defined($enc->{'ED_DEBVALID'}) && length($enc->{'ED_DEBVALID'}) > 0) {
			next if $now < $enc->{'ED_DEBVALID'};
		}
		if (defined($enc->{'ED_FINVALID'}) && length($enc->{'ED_FINVALID'}) > 0) {
			next if $now > $enc->{'ED_FINVALID'};
		}
		$encpds += $enc->{'ED_POIDSUNIT'};
		push(@needed, $encref);
	}
	my $listerefenc = join(', ', @needed) || "none"; # xxx réfléchir impact mise sous pli, en dur ou paramétrable dans table supports ?


	# Loop through the index file, gathering entries and counting the number of pages, etc...
#	my $host = hostname();
	my $numpgpli = 0;
	my $seqpgdoc = 0;
	my $idldoc = undef;
	open(my $fh, '<', $in) or die "Cannot open index file \"$in\": $!\n";
	my $prevseq = -1;
	my $count = 0;

	my $csv = Text::CSV->new({ binary => 1, sep_char => ';' });
	while (<$fh>) {
		# Parse the CSV data and extract all the fields.
		# The next three lines are needed for the Compuset case.
		# This is why we use Text::CSV::parse() and Text::CSV::fields()
		# instead of just Text::CSV::getline().
		s/^<50>//;
		s/<53>.*$//;
		s/\s*<[^>]*>\s*/;/g;

		$csv->parse($_);
		my @data = $csv->fields();

		# Truncate the name and city fields if necessary.
		if (length($data[5]) > 25) {
			warn "WARN : \"$data[5]\" truncated to 25 characters\n";
			$data[5] =~ s/^(.{25}).*$/$1/;
		}
		if (length($data[7]) > 30) {
			warn "WARN : \"$data[7]\" truncated to 30 characters\n";
			$data[7] =~ s/^(.{30}).*$/$1/;
		}

		my $first = $prevseq != $data[3];		# Is this the first page?
		$idldoc = $data[1] unless defined $idldoc;

		# XXX Ces deux valeurs sont identiques pour le moment car on a qu'un document
		# par pli, mais ce ne sera pas le cas une fois que le regroupement sera implémenté.
		if ($first) {
			$numpgpli = 1;
			$seqpgdoc = 1;
		} else {
			$numpgpli++;
			$seqpgdoc++;
		}

		my $entry = {
			ED_REFIDDOC	=> $data[0],
			ED_IDLDOC		=> $idldoc,
			ED_IDSEQPG	=> $data[2],
			ED_SEQDOC		=> $data[3],
			ED_CPDEST		=> $data[4],
			ED_VILLDEST	=> $data[5],
			ED_IDDEST		=> $data[6],
			ED_NOMDEST	=> $data[7],
			ED_IDEMET		=> $data[8],
			ED_DTEDTION	=> $data[9],
			ED_TYPPROD	=> $data[10],
			ED_PORTADR	=> $doc->{'ED_PORTADR'}, # vérifier qu'on peut le gérer comme ED_TYPPROD
			ED_ADRLN1		=> $data[12],
			ED_CLEGED1	=> $data[13],
			ED_ADRLN2		=> $data[14],
			ED_CLEGED2	=> $data[15],
			ED_ADRLN3		=> $data[16],
			ED_CLEGED3	=> $data[17],
			ED_ADRLN4		=> $data[18],
			ED_CLEGED4	=> $data[19],
			ED_ADRLN5		=> $data[20],
			ED_CORP		=> $data[21],
			ED_DOCLIB		=> $data[22],
			ED_REFIMP		=> $data[23],
			ED_ADRLN6		=> $data[24],
			ED_SOURCE		=> $data[25],
			ED_OWNER		=> $data[26],
			ED_HOST		=> $data[27],
			ED_IDIDX		=> $data[28],
			ED_CATDOC		=> $doc->{'ED_CATDOC'},
			#ED_CODRUPT	=>
			ED_SEQPGDOC	=> $seqpgdoc,
			ED_POIDSUNIT	=> $first ? $p1->{'ED_POIDSUNIT'} : $ps->{'ED_POIDSUNIT'},
			ED_NBENC		=> scalar @needed,				# ceci est un hack incompatible avec le regroupement de plis 
			ED_ENCPDS		=> $encpds,					# ceci est un hack incompatible avec le regroupement de plis
			ED_BAC_INSERT	=> $first ? $p1->{'ED_BAC_INSERT'} : $ps->{'ED_BAC_INSERT'},
			ED_TYPED		=> $doc->{'ED_TYPED'},
			ED_MODEDI		=> $doc->{'ED_MODEDI'},
			ED_FORMATP	=> $doc->{'ED_FORMATP'},
			ED_PGORIEN	=> $doc->{'ED_PGORIEN'},
#			ED_FORMDEF	=> $doc->{'ED_FORMDEF'},
#			ED_PAGEDEF	=> $doc->{'ED_PAGEDEF'},
#			ED_FORMS		=> $doc->{'ED_FORMS'},
			#ED_IDPLI		=>
			ED_NBDOCPLI	=> 1,		# XXX Sera différent de 1 quand on fera du regroupement
			ED_NUMPGPLI	=> $numpgpli,
			ED_LISTEREFENC	=> $listerefenc,
			ED_TYPOBJ		=> 'I'		# XXX Il nous manque des données pour ce champ
		};

		# On ne remplit le champ pré-imprimé que s'il n'est pas renseigné dans l'index.
		if (length($entry->{'ED_REFIMP'}) == 0) {
			$entry->{'ED_REFIMP'} = $first ? $doc->{'ED_REFIMP_P1'} : $doc->{'ED_REFIMP_PS'};
		}

		my @cols = keys(%$entry);
		my $sql = "INSERT INTO " . $cfg->{'EDTK_DBI_OUTMNGR'} . " (" . join(',', @cols) .
		    ") VALUES (" . join(',', ('?') x @cols) . ")";
		my $sth = $dbh->prepare_cached($sql);
# warn "INFO : insert Query = $sql\n";
# warn "INFO : insert values = ". dump (%$entry) . "\n"; # bug d'insertion de certaines valeurs dans Postgres
		$sth->execute(values(%$entry));

		$prevseq = $entry->{'ED_SEQDOC'};
		$count++;
	}
	close($fh);

	# Mise à jour de ED_NBPGDOC.
	my $sql = 'UPDATE ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' i SET ED_NBPGDOC = ' .
	    '(SELECT COUNT(*) FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} .
	    ' WHERE ED_IDLDOC = ? AND ED_SEQDOC = i.ED_SEQDOC) WHERE ED_IDLDOC = ?';
	$dbh->do($sql, undef, $idldoc, $idldoc);

	# Initialisation de ED_NBPGPLI à ED_NBPGDOC; sera différent si on fait du regroupement.
	$sql = 'UPDATE ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' i SET ED_NBPGPLI = ED_NBPGDOC ' .
	    'WHERE ED_IDLDOC = ?';
	$dbh->do($sql, undef, $idldoc);

	# Maintenant que l'on a calculé ED_NBPGPLI on peut mettre ED_MODEDI à jour.
	$sql = "UPDATE " . $cfg->{'EDTK_DBI_OUTMNGR'} . " SET " .
	    "ED_MODEDI = " .
	      "CASE ED_MODEDI WHEN 'S' THEN 'R' ELSE CASE ED_NBPGPLI WHEN 1 THEN 'R' ELSE 'V' END END " .
	    "WHERE ED_IDLDOC = ?";
	$dbh->do($sql, undef, $idldoc);
	warn "INFO : Imported $count pages\n";
	return ($idldoc, scalar @needed, $encpds);
}


sub omgr_lot($$$) {
	# rapprochement entre documents de l'index et table des lots => affectation du lot
	my ($dbh, $pdbh, $idldoc) = @_;
	my $cfg = config_read('EDTK_DB');

	# Sélection des lots appropriés.
	my $sql = 'SELECT ED_IDLOT, ED_IDAPPDOC, ED_CPDEST, ED_GROUPBY, ED_IDMANUFACT, ED_IDGPLOT ' .
	    'FROM EDTK_LOTS ORDER BY ED_PRIORITE';
	my $sth = $pdbh->prepare($sql);
	$sth->execute();
	while (my $lot = $sth->fetchrow_hashref()) {
		# On essaye de matcher des documents avec ce lot.
		$sql = 'UPDATE ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' SET ED_IDLOT = ? ' .
		    'WHERE ED_IDLDOC = ? AND ED_REFIDDOC LIKE ? AND ED_CPDEST LIKE ? AND ED_IDLOT IS NULL';
		my $num = $dbh->do($sql, undef, $lot->{'ED_IDLOT'}, $idldoc, $lot->{'ED_IDAPPDOC'},
		    $lot->{'ED_CPDEST'});

		if ($num > 0) {
			warn "INFO : Assigned $num pages to lot \"$lot->{'ED_IDLOT'}\"\n";
		}
	}

	# On assigne les entrées restantes au lot par défaut.
	my $num = $dbh->do("UPDATE " . $cfg->{'EDTK_DBI_OUTMNGR'} . " SET ED_IDLOT = ? " .
	    "WHERE ED_IDLDOC = ? AND ED_IDLOT IS NULL", undef, DEFLOT, $idldoc);
	if ($num > 0) {
		warn "WARN : Assigned $num remaining pages to default lot \"" . DEFLOT . "\"\n";
	}
}


sub omgr_get_next_filiere ($$){
	my ($pdbh, $filiere) = @_;

	# Récupération des paramètres d'assignation de la filiere.
	my ($ed_priorite, $ed_idmanufact, $ed_typed, $ed_modedi, $ed_idgplot, $ed_nbbacprn) 
			= $pdbh->selectrow_array('select ED_PRIORITE, ED_IDMANUFACT, ED_TYPED, ED_MODEDI, ED_IDGPLOT, ED_NBBACPRN from EDTK_FILIERES where ED_IDFILIERE =? ',
	    			undef, $filiere) or die $pdbh->errstr;
	# Récupération du 1er élément de la liste ordonnée des filieres.
	my $next_filiere 
			= $pdbh->selectrow_array('select ED_IDFILIERE from EDTK_FILIERES where ED_IDMANUFACT =? and ED_TYPED =? and ED_MODEDI =? and ED_NBBACPRN >=? and ED_ACTIF =? and ED_IDFILIERE !=? and ED_PRIORITE >? and (ED_IDGPLOT = ? or ED_IDGPLOT = ?) order by ED_PRIORITE',
	    			undef, $ed_idmanufact, $ed_typed, $ed_modedi, $ed_nbbacprn, 'O', $filiere, $ed_priorite, $ed_idgplot, '%');

     $next_filiere||=DEFFIL;
	warn "INFO : next_filiere is $next_filiere\n";
	return $next_filiere; 
}


sub omgr_filiere($$$$$$) {
	my ($dbh, $pdbh, $app, $idldoc, $numencs, $encpds) = @_;
	my $cfg = config_read('EDTK_DB');

	# Récupération des paramètres de l'application documentaire.
	my $doc = $pdbh->selectrow_hashref('SELECT * FROM EDTK_REFIDDOC WHERE ED_REFIDDOC = ?',
	    undef, $app) or die $pdbh->errstr;

#	# Récupération de la liste des encarts à joindre à ce document,
#	# et en déduire le poids supplémentaire à ajouter à chaque pli.
#	my @encarts = split(/,/, $doc->{'ED_REFIMP_REFIDDOC'});
#	my $encpds = 0;
#	my $sth = $pdbh->prepare('SELECT ED_POIDSUNIT FROM EDTK_SUPPORTS ' 
#			. 'WHERE ED_REFIMP = ?') 
#			or die "ERROR: select on supports failed " . $pdbh->errstr;
#	foreach my $encart (@encarts) {
#		my $pref = $pdbh->selectrow_arrayref($sth, undef, $encart) 
#			or die "ERROR: on support weight " . $pdbh->errstr;
#		$encpds += $pref->[0];
#	}

	# Récupération du support pour la première page et les suivantes.
	my $p1 = $pdbh->selectrow_hashref('SELECT * FROM EDTK_SUPPORTS WHERE ED_REFIMP = ?',
	    undef, $doc->{'ED_REFIMP_P1'}) or die $pdbh->errstr;
	my $ps = $pdbh->selectrow_hashref('SELECT * FROM EDTK_SUPPORTS WHERE ED_REFIMP = ?',
	    undef, $doc->{'ED_REFIMP_PS'}) or die $pdbh->errstr;

	# On recherche toutes les entrées qui ont un lot assigné 
	# mais pas encore de filière ? xxxxxxxxxxxx
	my $sql = 'SELECT DISTINCT ED_IDLOT FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} . 
	    ' WHERE ED_IDLDOC = ? AND ED_IDLOT IS NOT NULL AND ED_IDFILIERE IS NULL';
	my $lotids = $dbh->selectcol_arrayref($sql, undef, $idldoc);

	foreach my $lotid (@$lotids) {
		my $lot = $pdbh->selectrow_hashref('SELECT * FROM EDTK_LOTS WHERE ED_IDLOT = ?',
		    undef, $lotid) or die $pdbh->errstr;

		# On essaye maintenant de matcher les documents avec chacune des filières.
		my $sql = "SELECT * FROM EDTK_FILIERES WHERE ED_ACTIF = 'O' "
		    . "AND (ED_IDMANUFACT IS NULL OR ED_IDMANUFACT = '' OR ED_IDMANUFACT = ?) "
		    . "ORDER BY ED_PRIORITE";
		my $sth = $pdbh->prepare($sql) or die $pdbh->errstr;
		$sth->execute($lot->{'ED_IDMANUFACT'});

		# Les contraintes en nombre minimum/maximum de pages et plis sont vérifiées
		# uniquement lorsqu'on exporte les lots dans omgr_export() pour permettre
		# le regroupement.
		while (my $fil = $sth->fetchrow_hashref()) {
			# compatibilite ascendante
			if (defined $fil->{'ED_IDGPLOT'} && length($fil->{'ED_IDGPLOT'}) > 0) {
				if ($lot->{'ED_IDGPLOT'} ne $fil->{'ED_IDGPLOT'} and $fil->{'ED_IDGPLOT'} ne "%") {
					next;
				}
			}

			if (defined $fil->{'ED_NBENCMAX'} && length($fil->{'ED_NBENCMAX'}) > 0) {
				next if $numencs > $fil->{'ED_NBENCMAX'};
			}
			# La formule nous permettant de calculer le nombre de feuilles d'un pli.
			my $sqlnbfpli = "$numencs + "
					. ($fil->{'ED_MODEDI'} eq 'V' ? 'CEIL(ED_NBPGPLI / 2)' : 'ED_NBPGPLI');
			# La formule calculant le poids total du pli, et les valeurs associées.
			my $sqlpdspli  = "$encpds + $p1->{'ED_POIDSUNIT'} + $ps->{'ED_POIDSUNIT'} * ($sqlnbfpli - 1)";

			my $sql = "UPDATE " . $cfg->{'EDTK_DBI_OUTMNGR'} . " SET ED_IDFILIERE = ?, " .
			    "ED_FORMFLUX = ?, ED_NBFPLI = $sqlnbfpli, ED_PDSPLI = $sqlpdspli " .
			    "WHERE ED_IDLDOC = ? AND ED_IDLOT = ? AND ED_IDFILIERE IS NULL " .
			    "AND ED_MODEDI LIKE ? AND ED_TYPED LIKE ? ";
			my @vals = ($fil->{'ED_IDFILIERE'}, $fil->{'ED_FORMFLUX'}, $idldoc,
			    $lotid, $fil->{'ED_MODEDI'}, $fil->{'ED_TYPED'});
			if (defined $fil->{'ED_POIDS_PLI'} && length($fil->{'ED_POIDS_PLI'}) > 0) {
				$sql .= " AND $sqlpdspli <= ?";
				push(@vals, $fil->{'ED_POIDS_PLI'});
			}
			if (defined $fil->{'ED_FEUILPLI'} && length($fil->{'ED_FEUILPLI'}) > 0) {
				$sql .= " AND $sqlnbfpli <= ?";
				push(@vals, $fil->{'ED_FEUILPLI'});
			}
			my $num = $dbh->do($sql, undef, @vals);
			if ($num > 0) {
				warn "INFO : Assigned $num pages to filiere \"$fil->{'ED_IDFILIERE'}\" " .
				    "($fil->{'ED_DESIGNATION'})\n";
			}
		}
	}
}


sub omgr_export(%) {
	my (%conds) = @_;

	my $cfg = config_read('EDTK_DB');
	my $dbh = db_connect($cfg, 'EDTK_DBI_DSN', { AutoCommit => 0, RaiseError => 1 });
	my $pdbh= db_connect($cfg, 'EDTK_PARAM_DSN');
	# omgr_filiere2($dbh, $pdbh, $app, $idldoc, $numencs, $encpds);

	my $basedir = $cfg->{'EDTK_DIR_OUTMNGR'};

	my @done = ();
	eval {
		# Transformation des éventuels filtres utilisateurs en clause WHERE.
		my $user_where = join(' AND ', map { "$_ = ?" } keys(%conds));

		# Cette requête sélectionne les couples (idlot,idfiliere) contenant des plis non affectés.
		my $idsql = 'SELECT DISTINCT ED_IDLOT, ED_IDFILIERE FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} .
		    ' WHERE ED_IDLOT IS NOT NULL AND ED_IDFILIERE IS NOT NULL AND ED_SEQLOT IS NULL';
		if (length($user_where) > 0) {
			$idsql .= " AND $user_where";
		}
		my $ids = $dbh->selectall_arrayref($idsql, undef, values(%conds));

		foreach (@$ids) {    # il faut tenir compte de l'ordre de priorité des filières
			my ($idlot, $idfiliere) = @$_;

			CHECK_FIL:
			{
				warn "DEBUG: Considering couple : $idlot, $idfiliere\n";
				# La clause WHERE que l'on réutilise dans la plupart des requêtes afin de ne
				# traiter que les entrées qui nous intéressent.
				my $where = 'WHERE ED_IDLOT = ? AND ED_IDFILIERE = ? AND ED_SEQLOT IS NULL';
				if (length($user_where) > 0) {
					$where .= " AND $user_where";
				}
				my @wvals = ($idlot, $idfiliere, values(%conds));
	
				my $fil = $pdbh->selectrow_hashref('SELECT * FROM EDTK_FILIERES WHERE ED_IDFILIERE = ?',
				    undef, $idfiliere);
				my $lot = $pdbh->selectrow_hashref('SELECT * FROM EDTK_LOTS WHERE ED_IDLOT = ?',
				    undef, $idlot);
	
				# On verrouille la table $cfg->{'EDTK_DBI_OUTMNGR'} pour s'assurer que des entrées ne soient pas
				# ajoutées entre le moment ou on fait nos calculs et le moment ou on fait l'UPDATE.
				$dbh->do('LOCK TABLE ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' IN SHARE ROW EXCLUSIVE MODE');
	
				# Si le lot définit une colonne pour la valeur de ED_GROUPBY, on doit découper
				# les lots d'envoi en fonction de cette colonne.  De plus, on découpe toujours
				# par entité émettrice, format de papier, type de production et liste d'encarts.
				my @gcols = ('ED_CORP', 'ED_FORMATP', 'ED_TYPPROD', 'ED_LISTEREFENC');
	
				if (defined($lot->{'ED_GROUPBY'}) && length($lot->{'ED_GROUPBY'}) > 0) {
					push(@gcols, split(/,/, $lot->{'ED_GROUPBY'}));
				}
				my $groups = $dbh->selectall_arrayref("SELECT DISTINCT "
					. join(', ', @gcols) .  " FROM " . $cfg->{'EDTK_DBI_OUTMNGR'} 
					. " $where", { Slice => {} }, @wvals);
	
				foreach my $gvals (@$groups) {
					my $where2 = $where;	# vérifier qu'on l'utilise bien ...
					my @wvals2 = @wvals;
	
					if (keys(%$gvals) > 0) {
						# check if every value is defined and could be used (ED_LISTEREFENC could be defined or not)
						## which can produce this message : Issuing rollback() for database handle being DESTROY'd without explicit disconnect()
						foreach my $key (keys (%$gvals)) {
							if (defined $$gvals{$key}){} else {delete $$gvals{$key}}
						}
						
						push(@wvals2, values(%$gvals));
						$where2 .= ' AND ' . join(' AND ', map { "$_ = ?" } keys(%$gvals));
					}
	
					# On calcule le nombre de plis de chaque taille.
					my $innersql = 'SELECT DISTINCT ED_IDLDOC, ED_SEQDOC, ED_NBPGPLI FROM ' .
					    $cfg->{'EDTK_DBI_OUTMNGR'};
	
					my $sql = "SELECT COUNT(*), i.ED_NBPGPLI FROM ($innersql $where2) i " .
					    "GROUP BY i.ED_NBPGPLI ORDER BY i.ED_NBPGPLI DESC";
					my $res = $dbh->selectall_arrayref($sql, undef, @wvals2);
					next if @$res == 0; 
					
					# Calcul du nombre total de plis et de pages à notre disposition.
					my $availplis = sum(map { $$_[0] } @$res);
					my $availpgs = sum(map { $$_[0] * $$_[1] } @$res);
	
					# Aura-t-on besoin de repasser un traitement pour ce couple (idlot/idfiliere)
					# et pour le groupe définit par les colonnes de @gcols?
					my $more = 0;
	
					# Le nombre maximal de plis/pages que l'on peut prendre (soit la
					# limite de la filière, soit l'intégralité disponible).
					if (defined($fil->{'ED_MAXPLIS'}) && $availplis > $fil->{'ED_MAXPLIS'}) {
						$availplis = $fil->{'ED_MAXPLIS'};
						$more = 1;
					}
					
					if (defined($fil->{'ED_MAXFEUIL_L'})) {
						my $maxpgs = $fil->{'ED_MAXFEUIL_L'};
						if ($fil->{'ED_MODEDI'} eq 'V') {
							$maxpgs *= 2;
						}
						if ($availpgs > $maxpgs) {
							$availpgs = $maxpgs;
							$more = 1;
						}
					}
	
					my @plis = ();
					my $selplis = 0;
					my $selpgs = 0;
					foreach (@$res) {
						my ($numplis, $nbpgpli) = @$_;
	
						# Si on ne peut plus rajouter de plis ou de pages, on arrête.
						last if $availplis == 0 || $availpgs == 0;
						
						# Il n'y a pas suffisamment de pages disponibles pour ajouter de
						# pli de cette taille, on essaye donc avec de plus petits plis.
						next if $availpgs < $nbpgpli;
	
						my $nbplis = int($availpgs / $nbpgpli);
						if ($nbplis > $availplis) {
							$nbplis = $availplis;
						}
						if ($nbplis > $numplis) {
							$nbplis = $numplis;
						}
						my $nbpgs = $nbplis * $nbpgpli;
	
						push(@plis, [$nbplis, $nbpgpli]);
						$availplis -= $nbplis;
						$availpgs -= $nbpgs;
						$selplis += $nbplis;
						$selpgs += $nbpgs;
					}
	
					# On vérifie qu'on a sélectionné suffisamment de pages et de plis pour
					# remplir les limites basses de la filière si elles existent.
					my $min_feuilles = $fil->{'ED_MINFEUIL_L'} || 1;
					if ($selpgs < $min_feuilles) {
						warn "INFO : Not enough pages for filiere \"$idfiliere\" : "
							."got $selpgs, need $min_feuilles\n";
						$more = 1; # à vérifier qu'on en a bien besoin 
						# omgr_get_next_filiere($pdbh, $idfiliere);
						# reset filiere avec relance eval ou completion liste @$ids ?  xxxxxxxxxxxxx
						# cf 388 
							my $sql = "UPDATE " . $cfg->{'EDTK_DBI_OUTMNGR'} . " SET ED_IDFILIERE = ? " .
							    "WHERE ED_IDLOT = ? AND ED_IDFILIERE = ? AND ED_SEQLOT IS NULL ";
							my $next_filiere = omgr_get_next_filiere($pdbh, $idfiliere);
							my @vals= ($next_filiere, $idlot, $idfiliere);
							my $num = $dbh->do($sql, undef, @vals);
							$dbh->commit;
							warn "INFO : downgrade filiere to $next_filiere for $num plis\n";
							$idfiliere = $next_filiere;
						redo CHECK_FIL;
					}
	    				my $minplis = $fil->{'ED_MINPLIS'} || 1;
					if ($selplis < $minplis) {
						warn "INFO : Not enough plis for filiere \"$idfiliere\" : "
							."got $selplis, need $minplis\n";
						$more = 1; # à vérifier qu'on en a bien besoin
						# omgr_get_next_filiere($pdbh, $idfiliere);
						# reset filiere avec relance eval ou completion liste @$ids ?  xxxxxxxxxxxxx
						# cf 388 
							my $sql = "UPDATE " . $cfg->{'EDTK_DBI_OUTMNGR'} . " SET ED_IDFILIERE = ? " .
							    "WHERE ED_IDLOT = ? AND ED_IDFILIERE = ? AND ED_SEQLOT IS NULL ";
							my $next_filiere = omgr_get_next_filiere($pdbh, $idfiliere);
							my @vals = ($next_filiere, $idlot, $idfiliere);
							my $num = $dbh->do($sql, undef, @vals);
							$dbh->commit;
							warn "INFO : downgrade filiere to $next_filiere for $num plis\n";
							$idfiliere = $next_filiere;
						redo CHECK_FIL;
					}

					my $seqlot = get_seqlot($dbh);
					my $name = "$gvals->{'ED_CORP'}.$lot->{'ED_IDMANUFACT'}.$seqlot.$lot->{'ED_LOTNAME'}.$fil->{'ED_IDFILIERE'}";
	
					# Préparation de l'ordre de tri pour cette filière.
					my $order;
					if (defined $fil->{'ED_SORT'} && length($fil->{'ED_SORT'}) > 0) {
						$order = $fil->{'ED_SORT'};
						if (defined $fil->{'ED_DIRECTION'} && length($fil->{'ED_DIRECTION'}) > 0) {
							$order .= " $fil->{'ED_DIRECTION'}";
						}
					} else {
						$order = "ED_IDLDOC, ED_SEQDOC";
					}
	
					# La date d'aujourd'hui. 
					my $dtlot = sprintf("%04d%02d%02d", Today());
	
					foreach (@plis) {
						my ($nbplis, $nbpgpli) = @$_;
	
						warn "DEBUG: Assigning $nbplis of $nbpgpli pages each to lot $seqlot\n";
						# Cette requête sélectionne les N premiers plis non affectés
						# d'une taille donnée, les plis étant uniquement identifiés avec
						# un identifiant de lot de document + un identifiant de pli.
						$innersql = "SELECT j.ED_IDLDOC, j.ED_SEQDOC FROM (" .
						  "SELECT i.ED_IDLDOC, i.ED_SEQDOC, ROW_NUMBER() " .
						  "OVER (ORDER BY PGNUM) AS PLINUM FROM " .
						    "(SELECT " . $cfg->{'EDTK_DBI_OUTMNGR'} . ".*, ROW_NUMBER() OVER (ORDER BY $order) AS PGNUM " .
						    "FROM " . $cfg->{'EDTK_DBI_OUTMNGR'} . " $where2 AND ED_NBPGPLI = ?) i " .
						  "WHERE ED_SEQPGDOC = 1) j WHERE PLINUM <= ?";
	
						# On assigne le lot à tous les plis sélectionnés. On en profite
						# aussi pour positionner la date de création du lot.
						$sql = "UPDATE " . $cfg->{'EDTK_DBI_OUTMNGR'} . " SET ED_SEQLOT = ?, ED_DTLOT = ? " .
						    "WHERE (ED_IDLDOC, ED_SEQDOC) IN ($innersql)";
						my $count = $dbh->do($sql, undef, $seqlot, $dtlot, @wvals2, $nbpgpli, $nbplis);
						my $pages = $nbplis * $nbpgpli;
						if ($count != $pages) {
							die "Unexpected UPDATE row count ($count != $pages)\n";
						}
					}
					warn "INFO : Assigned $selpgs pages to lot \"$name\"\n";
	
					# Calcul des identifiants de pli.  XXX Devrait être fait autrement...
					$sql = "SELECT ED_IDLDOC, ED_SEQDOC, " .
					           "DENSE_RANK() OVER (ORDER BY ED_IDLDOC, ED_SEQDOC) AS ED_IDPLI " .
						 "FROM " . $cfg->{'EDTK_DBI_OUTMNGR'} . " WHERE ED_SEQLOT = ? ORDER BY $order";
					my $rows = $dbh->selectall_arrayref($sql, { Slice => {} }, $seqlot);
	
					$sql = 'UPDATE ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' SET ED_IDPLI = ? ' .
					  'WHERE ED_IDLDOC = ? AND ED_SEQDOC = ? AND ED_SEQLOT = ?';
					my $sth = $dbh->prepare($sql);
					foreach my $row (@$rows) {
						$sth->execute($row->{'ED_IDPLI'}, $row->{'ED_IDLDOC'},
						    $row->{'ED_SEQDOC'}, $seqlot);
					}
	
					# Récupération de la liste des imprimés nécessaires pour ce lot.
					$sql = 'SELECT DISTINCT ED_REFIMP FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} .
					    ' WHERE ED_SEQLOT = ?';
					my @refimps = $dbh->selectrow_array($sql, undef, $seqlot);
	
					# Calcul du nombre total de feuilles dans le lot.
					$sql = 'SELECT SUM(i.ED_NBFPLI) FROM ' .
					    '(SELECT DISTINCT ED_IDLDOC, ED_SEQDOC, ED_NBFPLI ' .
					      'FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' WHERE ED_SEQLOT = ?) i';
					my ($nbfeuillot) = $dbh->selectrow_array($sql, undef, $seqlot);
	
					# Extraction des données.
					my $lotdir = "$basedir/$name";
					mkdir("$lotdir") or die "Cannot create directory \"$lotdir\": $!\n";
					my $file = "$name.idx";
					warn "INFO : Creating index file \"$file\"\n";
					$sql = "SELECT * FROM " . $cfg->{'EDTK_DBI_OUTMNGR'} .
					    " WHERE ED_SEQLOT = ? ORDER BY $order";
					$sth = $dbh->prepare($sql);
					$sth->execute($seqlot);
	
					open(my $fh, ">$lotdir/$file") or die $!;
					# Génération de la ligne de header.
					my $csv = Text::CSV->new({ binary => 1, eol => "\n", quote_space => 0 });
					$csv->print($fh, [map { $$_[0] } @INDEX_COLS]);
					my $doclib;
					while (my $row = $sth->fetchrow_hashref()) {
						# Gather the values in the same order as @INDEX_COLS.
						my @fields = map { $row->{$$_[0]} } @INDEX_COLS;
						$csv->print($fh, \@fields);
	
						$doclib = $row->{'ED_DOCLIB'} unless defined $doclib;
					}
					close($fh);
	
					# Generate a job ticket file.
					$file = "$name.job";
					warn "INFO : Creating job ticket file \"$file\"\n";
					my @jobfields = (
						['ED_IDLOT',		$idlot],
						['ED_SEQLOT',		$seqlot],
						['ED_CORP',		$gvals->{'ED_CORP'}],
						['ED_IDAPPDOC',	$lot->{'ED_IDAPPDOC'}],
						['ED_CPDEST',		$lot->{'ED_CPDEST'}],
						['ED_GROUPBY',		$lot->{'ED_GROUPBY'}],
						['ED_IDMANUFACT',	$lot->{'ED_IDMANUFACT'}],
						['ED_LOTNAME',		$lot->{'ED_LOTNAME'}],
						['ED_IDFILIERE',	$idfiliere],
						['ED_DESIGNATION',	$fil->{'ED_DESIGNATION'}],
						['ED_MODEDI',		$fil->{'ED_MODEDI'}],
						['ED_TYPED',		$fil->{'ED_TYPED'}],
						['ED_NBBACPRN',	$fil->{'ED_NBBACPRN'}],
						['ED_MINFEUIL_L',	$fil->{'ED_MINFEUIL_L'}],
						['ED_MAXFEUIL_L',	$fil->{'ED_MAXFEUIL_L'}],
						['ED_FEUILPLI',	$fil->{'ED_FEUILPLI'}],
						['ED_MINPLIS',		$fil->{'ED_MINPLIS'}],
						['ED_MAXPLIS',		$fil->{'ED_MAXPLIS'}],
						['ED_POIDS_PLI',	$fil->{'ED_POIDS_PLI'}],
						['ED_REF_ENV',		$fil->{'ED_REF_ENV'}],
						['ED_FORMFLUX',	$fil->{'ED_FORMFLUX'}],
						['ED_POSTCOMP',	$fil->{'ED_POSTCOMP'}],
						['ED_NBFEUILLOT',	$nbfeuillot],
						['ED_NBPLISLOT',	$selplis],
						['ED_FORMATP',		$gvals->{'ED_FORMATP'}],
						['ED_LISTEREFENC',	$gvals->{'ED_LISTEREFENC'} || ""],
						['ED_LISTEREFIMP',	join(', ', @refimps)],
						['ED_DTLOT',		$dtlot]
					);
					open($fh, ">$lotdir/$file") or die $!;
					$csv->print($fh, [map { $$_[0] } @jobfields]);
					$csv->print($fh, [map { $$_[1] } @jobfields]);
					close($fh);
	
					# Add this lot to the list of created ones.
					$dbh->commit;
					push(@done, [$name, $doclib]);
	
					# On reboucle le traitement si l'on a atteint les limites maximales en
					# pages/plis et que l'on doit traiter d'autres lots.
					redo if $more;
				}
			}
		}
	};
	if ($@) {
		warn "ERROR: $@\n";
		eval { $dbh->rollback };
	}
	return @done;
}


sub omgr_depot_poste($$$) {
	my ($dbh, $seqlot, $dt_depot) = @_;
	my $cfg = config_read('EDTK_DB');
	
	$dt_depot=~/^\d{8}$/ or die "ERROR: $dt_depot should be formated as yyyymmdd\n";

	my $sql = 'UPDATE ' . $cfg->{'EDTK_DBI_OUTMNGR'} . ' SET ED_DTPOSTE = ? WHERE ED_SEQLOT like ?';
	$dbh->do($sql, undef, $dt_depot, $seqlot) or die "ERROR: can't update $seqlot with $dt_depot";	
}


sub omgr_purge_db($$) {
	my ($dbh, $value) = @_;
	my $cfg = config_read('EDTK_STATS');
	my $type = "";
	my $sql;

	if (length ($value) == 6) {
		$type = "SEQLOT";
		warn "INFO : suppr $type $value from EDTK_STATS_OUTMNGR\n";
		$sql = 'DELETE FROM ' . $cfg->{'EDTK_STATS_OUTMNGR'} . ' WHERE ED_SEQLOT = ?';
		$dbh->do($sql, undef, $value) or die "ERROR: suppr $type $value from EDTK_STATS_OUTMNGR\n";

	} elsif (length ($value) == 16) { # 1282152443057128
		$type = "SNGL_ID";	# EDTK_STATS_TRACKING
		warn "INFO : suppr $type $value from EDTK_STATS_TRACKING\n";
		$sql = 'DELETE FROM ' . $cfg->{'EDTK_STATS_TRACKING'} . ' WHERE ED_SNGL_ID = ?';
		$dbh->do($sql, undef, $value) or die "ERROR: suppr $type $value from EDTK_STATS_TRACKING\n";

		warn "INFO : suppr $type $value from EDTK_STATS_OUTMNGR\n";
		$sql = 'DELETE FROM '.$cfg->{'EDTK_STATS_OUTMNGR'}.' WHERE ED_IDLDOC = ?';
		$dbh->do($sql, undef, $value) or die "ERROR: suppr $type $value from EDTK_STATS_OUTMNGR\n";

	} else {
		die "ERROR: $value doesn't seem to be SNGL_ID or SEQLOT";	
	}
}


sub omgr_check_seqlot_ref ($$){
	my ($dbh, $value) = @_;
	my $cfg = config_read('EDTK_STATS');
	my $type = "SEQLOT";
	my $sql;

	if (length ($value) == 6) {
		warn "INFO : check $type $value refs from EDTK_STATS_OUTMNGR\n";
		$sql = 'SELECT ED_REFIDDOC, ED_IDLDOC, ED_SEQLOT FROM ' 
			. $cfg->{'EDTK_STATS_OUTMNGR'} . ' WHERE ED_SEQLOT = ? GROUP BY ED_REFIDDOC, ED_IDLDOC, ED_SEQLOT';

#select ed_refiddoc, ed_idldoc, ed_seqlot 
#	   from ( select distinct ed_idldoc from edtk_index where ed_seqlot = '052661' ) i
# where ed_idldoc = i.ed_idldoc
# group by i.ed_refiddoc, i.ed_idldoc, i.ed_seqlot; 

		my $sth = $dbh->prepare($sql);
		$sth->execute($value);
	
		my $rows = $sth->fetchall_arrayref();

		return $rows;

	} else {
		die "ERROR: $value doesn't seem to be SEQLOT\n";	
	}
}


# Purge doclibs that are no longer referenced in the database.
sub omgr_purge_fs($) {
	my ($dbh) = @_;

	my $cfg = config_read('EDTK_DB');
	my $dir = $cfg->{'EDTK_DIR_DOCLIB'};
	my @doclibs = glob("$dir/*.pdf");

	my $sql = 'SELECT DISTINCT ED_DOCLIB FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} .
	    ' WHERE ED_SEQLOT IS NULL';

	# Transform the list of needed doclibs into a hash for speed.
	my %needed = map { $_->[0] => 1 } @{$dbh->selectall_arrayref($sql)};

	my @torm = ();
	foreach my $path (@doclibs) {
		my $file = basename($path);
		if ($file =~ /^DCLIB_/) {
			if (!$needed{$file}) {
				push(@torm, $path);
			}
		} else {
			warn "WARN : Unexpected filename : \"$file\"\n";
		}
	}
	return @torm;
}


sub omgr_referent_stats {
	my ($dbh, $pdbh) = @_;
	my $cfg = config_read('EDTK_DB');
	my ($sql, $key);

	$sql = "SELECT A.ED_MAIL_REFERENT, A.ED_REFIDDOC ";
	$sql .="FROM EDTK_REFIDDOC A, EDTK_INDEX B ";
	$sql .="WHERE A.ED_REFIDDOC = B.ED_REFIDDOC ";
	$sql .="AND A.ED_MASSMAIL != 'N' AND A.ED_MAIL_REFERENT IS NOT NULL ";
	$sql .="AND B.ED_SEQLOT IS NULL AND B.ED_DTLOT IS NULL ";
	$sql .="GROUP BY A.ED_MAIL_REFERENT, A.ED_REFIDDOC ";
	$sql .="ORDER BY A.ED_MAIL_REFERENT ";

	my $sth = $dbh->prepare($sql);
	$sth->execute();

	my $rows = $sth->fetchall_arrayref();
	return $rows;
}


sub omgr_stats($$$$) {
	my ($dbh, $pdbh, $period, $typeRqt) = @_;
	$typeRqt = $typeRqt || "idlot";
	my $cfg = config_read('EDTK_DB');
	my ($sql, $key);
	my $time = time;
	my ($year,$month,$day, $hour,$min,$sec, $doy,$dow,$dst) =
		Gmtime($time);
	my ($week,) = Week_of_Year($year,$month,$day);
	
	if ($period =~ /^day$/i) {
		$key = sprintf ("%02d%1d", $week, $dow );
	} elsif ($period =~ /^week$/i){
		$key = sprintf("%02d", $week);
	} elsif ($period =~ /^all$/i){
		$key="";
	} elsif ($period =~ /^\d+$/){
		$key = $period;
	} else {
		warn "WARN : implémentation en attente évolution base\n";
	}

	if ($typeRqt !~/idlot/i) {
		$sql = "SELECT ED_IDLOT, ED_CORP, ";
	} else { 
		$sql = "SELECT ED_IDLOT, ED_CORP, ED_SEQLOT, ";
	}	
	$sql .="COUNT (DISTINCT ED_IDLDOC||TO_CHAR(ED_SEQDOC,'FM0000000')), ";	# NB PLIS
	$sql .="COUNT (DISTINCT ED_IDLDOC||TO_CHAR(ED_SEQDOC,'FM0000000')), ";	# NB DOCS
	$sql .="SUM(ED_NBFPLI), "; 						# NB FEUILLES
	$sql .="SUM(ED_NBPGDOC), ";						# NB FACES IMPRIMEES
	$sql .="CASE ED_MODEDI WHEN 'R' THEN 1 ELSE 2 END * SUM(ED_NBFPLI) ";	# NB FACES

	if ($typeRqt !~/idlot/i) {
		$sql .=", ED_MODEDI ";
		$sql .=" FROM " . $cfg->{'EDTK_DBI_OUTMNGR'};
		$sql .=" GROUP BY ED_CORP, ED_IDLOT, ED_MODEDI ";
		$sql .=" ORDER BY ED_CORP, ED_IDLOT, ED_MODEDI ";
	} else { 
		$sql .=", ED_IDFILIERE ";
		$sql .=" FROM " . $cfg->{'EDTK_DBI_OUTMNGR'};
		$sql .=" WHERE ED_SEQLOT LIKE ? AND ED_SEQPGDOC = 1 ";
		$sql .=" GROUP BY ED_CORP, ED_IDLOT, ED_SEQLOT, ED_IDFILIERE, ED_MODEDI ";
		$sql .=" ORDER BY ED_CORP, ED_IDFILIERE, ED_SEQLOT ";
	}

	my $sth = $dbh->prepare($sql);
	if ($typeRqt !~/idlot/i) {
		$sth->execute();
	} else { 
		$sth->execute("$key%");
	}	

	my $rows = $sth->fetchall_arrayref();
	foreach my $row (@$rows) {
		my ($lot) = $pdbh->selectrow_array('SELECT ED_LOTNAME FROM EDTK_LOTS WHERE ED_IDLOT = ?',
		    undef, @$row[0]);
		@$row[0] = $lot;
	}
	return $rows;
}


sub omgr_lot_pending($) {
	my ($dbh) = @_;
	my $cfg = config_read('EDTK_DB');

	#-- RECHERCHE DES DOCUMENTS EN ATTENTE DE LOTISSEMENT -- 
	my $ctrl_sql = 'SELECT ED_CORP, ED_REFIDDOC, ED_IDLDOC, ED_DTEDTION FROM ' . $cfg->{'EDTK_DBI_OUTMNGR'} 
	    . ' WHERE ED_SEQLOT IS NULL'
	    . ' GROUP BY ED_CORP, ED_REFIDDOC, ED_DTEDTION, ED_IDLDOC'
	    . ' ORDER BY ED_CORP, ED_REFIDDOC, ED_DTEDTION, ED_IDLDOC';

	my $sth = $dbh->prepare($ctrl_sql);
	$sth->execute();

	my $rows = $sth->fetchall_arrayref();
	return $rows;
}

# PRIVATE, NON-EXPORTED FUNCTIONS BELOW.

# Compute a new and unique lot sequence.
sub get_seqlot {
	my $dbh = shift;

	my $sql;
	if ($dbh->{'Driver'}->{'Name'} eq 'Oracle') {
		$sql = "SELECT to_char(sysdate, 'IWD') || " .
		    "to_char(EDTK_IDLOT.NEXTVAL, 'FM000') FROM dual";
	} else {
		$sql = "SELECT to_char(current_date, 'IWID') || " .
		    "to_char(nextval('EDTK_IDLOT'), 'FM000')";
	}
	my ($seqlot) = $dbh->selectrow_array($sql);
	return $seqlot;
}


sub print_All_rTab($){
	# EDITION DE L'ENSEMBLE DES DONNÉES D'UN TABLEAU PASSÉ EN REFÉRENCE
	#  affichage du tableau en colonnes 
	my $rTab=shift;

	for (my $i=0 ; $i<=$#{$rTab} ; $i++) {
		my $cols = $#{$$rTab[$i]};
		print "\n$i:\t";
			
		for (my $j=0 ;$j<=$cols ; $j++){
			print "$$rTab[$i][$j]" if (defined $$rTab[$i][$j]);
		}
	}
	print "\n";
1;
}


1;
