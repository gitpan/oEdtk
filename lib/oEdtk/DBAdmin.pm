package oEdtk::DBAdmin;

use oEdtk::Config	qw(config_read);
use strict;
use warnings;

use DBI;

use Exporter;

our $VERSION		= 0.17;
our @ISA			= qw(Exporter);
our @EXPORT_OK		= qw(db_connect
			     historicize_table
			     create_lot_sequence
			     create_SCHEMA
			     create_table_ACQUIT
			     create_table_DATAGROUPS
			     create_table_FILIERES
			     create_table_INDEX
			     create_table_LOTS
			     create_table_PARA
			     create_table_REFIDDOC
			     create_table_SUPPORTS
			     create_table_TRACKING
			     move_table
			     @INDEX_COLS);
 
sub db_connect {
	my ($cfg, $dsnvar, $dbargs) = @_;

	# This avoids problems with PostgreSQL where in some cases, the column
	# names are lowercase instead of uppercase as we assume everywhere.
	$dbargs->{'FetchHashKeyName'} = 'NAME_uc';

	# Connect to the database.
	my $dbh = _db_connect1($cfg, $dsnvar, $dbargs);

    	# If we could not connect to the database server, try
	# to connect to the backup database server if there is one.
	if (!defined $dbh) {
		if (defined $cfg->{"${dsnvar}_BAK"}) { # il faudrait ajouter le paramétrage dans la base de backup (procédure de création de cette base)
			warn "ERROR: Could not connect to main database server: $DBI::errstr\n";
			$dbh = _db_connect1($cfg, "${dsnvar}_BAK", $dbargs);
			if (!defined $dbh) {
				die "ERROR: Could not connect to backup database server: $DBI::errstr\n";
			}
		} else {
			die "ERROR: Could not connect to database server: $DBI::errstr\n";
		}
	}
	return $dbh;
}

sub _db_connect1 {
	my ($cfg, $dsnvar, $dbargs) = @_;

	my $dsn = $cfg->{$dsnvar};

	warn "INFO : Connecting to DSN $dsn...\n";
	return DBI->connect($dsn, $cfg->{"${dsnvar}_USER"}, $cfg->{"${dsnvar}_PASS"}, $dbargs);
}


sub create_table_TRACKING {
	my ($dbh, $table, $maxkeys) = @_;

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_TSTAMP VARCHAR2(14) NOT NULL";	# Timestamp of event
	$sql .= ", ED_USER VARCHAR2(10) NOT NULL";	# Job request user 
	$sql .= ", ED_SEQ INTEGER NOT NULL";		# Sequence
	$sql .= ", ED_SNGL_ID VARCHAR2(17) NOT NULL";# Single ID : format YWWWDHHMMSSPPPP.U (compuset se limite ? 16 digits : 15 entiers, 1 decimal)
	$sql .= ", ED_APP VARCHAR2(20) NOT NULL";	# Application name
	$sql .= ", ED_MOD_ED CHAR";				# Editing mode (Batch, Tp, Web, Mail)
	$sql .= ", ED_JOB_EVT CHAR";				# Level of the event (Spool, Document, Line, Warning, Error)
	$sql .= ", ED_CORP VARCHAR2(8) NOT NULL";	# Entity related to the document
	$sql .= ", ED_SOURCE VARCHAR2(128)";		# Input stream of this document
	$sql .= ", ED_OBJ_COUNT INTEGER";			# Number of objects attached to the event
	$sql .= ", ED_HOST VARCHAR2(32)";			# Input stream of this document

	foreach my $i (0 .. $maxkeys) {
		$sql .= ", ED_K${i}_NAME VARCHAR2(8)";	# Name of key $i
		$sql .= ", ED_K${i}_VAL VARCHAR2(128)";	# Value of key $i
	}
	$sql .= ")";	#, CONSTRAINT pk_$ENV{EDTK_DBI_TABLENAME} PRIMARY KEY (ED_TSTAMP, ED_PROC, ED_SEQ)";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub _drop_table_TRACKING {
	my ($dbh, $table) = @_;

	$dbh->do("DROP TABLE $table") or die $dbh->errstr;
}


sub historicize_table ($$$){
	my ($dbh, $table, $suffixe) = @_;
	my $table_cible =$table."_".$suffixe;
		
	move_table ($dbh, $table, $table_cible, '-create');	

	my $sql = "TRUNCATE TABLE $table";
	$dbh->do($sql, undef) or die $dbh->errstr;	
}


sub move_table ($$$;$){
	my ($dbh, $table_source, $table_cible, $create_option) = @_;
	$create_option ||= "";
	my $sql_create ="CREATE TABLE ".$table_cible." AS SELECT * FROM ".$table_source;
	my $sql_insert ="INSERT INTO  ".$table_cible." SELECT * FROM ".$table_source;

	if ($create_option =~/-create/i) {
		$dbh->do($sql_create, undef, ) or die $dbh->errstr;	
	} else {
		$dbh->do($sql_insert, undef, ) or die $dbh->errstr;	
	}
}


sub create_table_FILIERES {
	my $dbh = shift;
	my $table = "EDTK_FILIERES";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_IDFILIERE VARCHAR2(5) NOT NULL";	# filiere id   ALTER table edtk_filieres modify ED_IDFILIERE VARCHAR2(5);
	$sql .= ", ED_IDMANUFACT VARCHAR2(16)";	  
	$sql .= ", ED_DESIGNATION VARCHAR2(64)";		# 
	$sql .= ", ED_ACTIF CHAR NOT NULL";			# Flag indiquant si la filiere est active ou pas 
	$sql .= ", ED_PRIORITE INTEGER NOT NULL";		# Ordre d'execution des filieres 
	$sql .= ", ED_TYPED CHAR NOT NULL";			# 
	$sql .= ", ED_MODEDI CHAR NOT NULL";			# 
	$sql .= ", ED_IDGPLOT VARCHAR2(16) NOT NULL";	# alter table EDTK_FILIERES add ED_IDGPLOT VARCHAR2(16) 
	$sql .= ", ED_NBBACPRN INTEGER NOT NULL";		# 
	$sql .= ", ED_NBENCMAX INTEGER";
	$sql .= ", ED_MINFEUIL_L INTEGER"; 
	$sql .= ", ED_MAXFEUIL_L INTEGER"; 
	$sql .= ", ED_FEUILPLI INTEGER";
	$sql .= ", ED_MINPLIS INTEGER";
	$sql .= ", ED_MAXPLIS INTEGER NOT NULL";
	$sql .= ", ED_POIDS_PLI INTEGER";				# poids maximum du pli dans la filiere
	$sql .= ", ED_REF_ENV VARCHAR2(8) NOT NULL";
	$sql .= ", ED_FORMFLUX VARCHAR2(3) NOT NULL";
	$sql .= ", ED_SORT VARCHAR2(128) NOT NULL";
	$sql .= ", ED_DIRECTION VARCHAR2(4) NOT NULL";
	$sql .= ", ED_POSTCOMP VARCHAR2(8) NOT NULL";
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_LOTS {
	my $dbh = shift;
	my $table = "EDTK_LOTS";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_IDLOT VARCHAR2(8) NOT NULL"; 
	$sql .= ", ED_PRIORITE INTEGER NOT NULL";  
	$sql .= ", ED_IDAPPDOC VARCHAR2(20) NOT NULL";
	$sql .= ", ED_CPDEST VARCHAR2(6) NOT NULL"; 
	$sql .= ", ED_GROUPBY VARCHAR2(16)"; 
	$sql .= ", ED_IDMANUFACT VARCHAR2(16) NOT NULL"; 
	$sql .= ", ED_LOTNAME VARCHAR2(16) NOT NULL";	# alter table EDTK_LOTS add ED_LOTNAME VARCHAR2(16);  alter table EDTK_LOTS modify ED_LOTNAME VARCHAR2(16) NOT NULL;
	$sql .= ", ED_IDGPLOT VARCHAR2(16) NOT NULL";
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_REFIDDOC {
	my $dbh = shift;
	my $table = "EDTK_REFIDDOC";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_REFIDDOC VARCHAR2(20) NOT NULL"; 
	$sql .= ", ED_CORP VARCHAR2(8) NOT NULL";		# Entity related to the document
	$sql .= ", ED_CATDOC CHAR NOT NULL";  
	$sql .= ", ED_PORTADR CHAR NOT NULL";  
	$sql .= ", ED_MASSMAIL CHAR NOT NULL";
	$sql .= ", ED_EDOCSHARE CHAR NOT NULL";  
	$sql .= ", ED_TYPED CHAR NOT NULL";  
	$sql .= ", ED_MODEDI CHAR NOT NULL";  
	$sql .= ", ED_PGORIEN VARCHAR2(2)";
	$sql .= ", ED_FORMATP VARCHAR2(2)"; 
	$sql .= ", ED_REFIMP_P1 VARCHAR2(16)"; 
	$sql .= ", ED_REFIMP_PS VARCHAR2(16)"; 
	$sql .= ", ED_REFIMP_REFIDDOC VARCHAR2(64)"; 
	$sql .= ", ED_MAIL_REFERENT VARCHAR2(300)";		# referent mail for doc validation

	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_SUPPORTS {
	my $dbh = shift;
	my $table = "EDTK_SUPPORTS";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_REFIMP VARCHAR2(16) NOT NULL"; 
	$sql .= ", ED_TYPIMP CHAR NOT NULL";  
	$sql .= ", ED_FORMATP VARCHAR2(2) NOT NULL";
	$sql .= ", ED_POIDSUNIT INTEGER NOT NULL";  
	$sql .= ", ED_FEUIMAX INTEGER";  
	$sql .= ", ED_POIDSMAX INTEGER";  
	$sql .= ", ED_BAC_INSERT INTEGER";  
	$sql .= ", ED_COPYGROUP VARCHAR2(16)";
	$sql .= ", ED_OPTCTRL VARCHAR2(8)"; 
	$sql .= ", ED_DEBVALID VARCHAR2(8)"; 
	$sql .= ", ED_FINVALID VARCHAR2(8)"; 
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}

our @INDEX_COLS = (
	# SECTION COMPOSITION DE L'INDEX
	['ED_REFIDDOC', 'VARCHAR2(20) NOT NULL'],# identifiant dans le référentiel de document
	['ED_IDLDOC', 'VARCHAR2(17) NOT NULL'],	# Identifiant du document dans le lot de mise en page ED_SNGL_ID
	['ED_IDSEQPG', 'INTEGER NOT NULL'],	# Sequence Numéro de séquence de page dans le lot de mise en page
	['ED_SEQDOC', 'INTEGER NOT NULL'],		# Numéro de séquence du document dans le lot

	['ED_CPDEST', 'VARCHAR2(8)'],			# Code postal Destinataire
	['ED_VILLDEST', 'VARCHAR2(25)'],		# Ville destinataire
	['ED_IDDEST', 'VARCHAR2(25)'],		# Identifiant du destinataire dans le système de gestion
	['ED_NOMDEST', 'VARCHAR2(30)'],		# Nom destinataire
	['ED_IDEMET', 'VARCHAR2(10)'],		# identifiant de l'émetteur
	['ED_DTEDTION', 'VARCHAR2(8) NOT NULL'],# date d'édition, celle qui figure sur le document
	['ED_TYPPROD', 'CHAR'],				# type de production associée au lot
	['ED_PORTADR', 'CHAR'],				# indicateur de document porte adresse
	['ED_ADRLN1', 'VARCHAR2(38)'],		# ligne d'adresse 1
	['ED_CLEGED1', 'VARCHAR2(20)'],		# clef pour système d'archivage
	['ED_ADRLN2', 'VARCHAR2(38)'],		# ligne d'adresse 2
	['ED_CLEGED2', 'VARCHAR2(20)'],		# clef pour système d'archivage
	['ED_ADRLN3', 'VARCHAR2(38)'],		# ligne d'adresse 3
	['ED_CLEGED3', 'VARCHAR2(20)'],		# clef pour système d'archivage
	['ED_ADRLN4', 'VARCHAR2(38)'],		# ligne d'adresse 4
	['ED_CLEGED4', 'VARCHAR2(20)'],		# clef pour système d'archivage
	['ED_ADRLN5', 'VARCHAR2(38)'],		# ligne d'adresse 5
	['ED_CORP', 'VARCHAR2(20)'],			# sociét? émettrice de la page
	['ED_DOCLIB', 'VARCHAR2(32)' ],		# merge library compuset associée ? la page
	['ED_REFIMP', 'VARCHAR2(8)'],			# référence de pr?-imprim? ou d'imprim? ou d'encart
	['ED_ADRLN6', 'VARCHAR2(38)'],		# ligne d'adresse 6
	['ED_SOURCE', 'VARCHAR2(8) NOT NULL'],	# Source de l'index
	['ED_OWNER', 'VARCHAR2(10)'],			# propriétaire du document (utilisation en gestion / archivage de documents)
	['ED_HOST', 'VARCHAR2(32)'],			# Hostname de la machine d'ou origine cette entrée
	['ED_IDIDX', 'VARCHAR2(7) NOT NULL'],	# identifiant de l'index

	# SECTION LOTISSEMENT DE L'INDEX
	['ED_IDLOT', 'VARCHAR2(6)'],			# identifiant du lot
	['ED_SEQLOT', 'VARCHAR2(7)'],			# identifiant du lot de mise sous plis (sous-lot) ALTER table edtk_index modify ED_SEQLOT VARCHAR2(7);
	['ED_DTLOT', 'VARCHAR2(8)'],			# date de la création du lot de mise sous plis
	['ED_IDFILIERE', 'VARCHAR2(5)'],		# identifiant de la filière de production     	ALTER table edtk_index modify ED_IDFILIERE VARCHAR2(5);
	['ED_CATDOC', 'CHAR'],				# catégorie de document
	['ED_CODRUPT', 'CHAR'],				# code forçage de rupture
	['ED_SEQPGDOC', 'INTEGER'],			# numéro de séquence de page dans le document
	['ED_NBPGDOC', 'INTEGER'],			# nombre de page (faces) du document
	['ED_POIDSUNIT', 'INTEGER'],			# poids de l'imprim? ou de l'encart en mg
	['ED_NBENC', 'INTEGER'],				# nombre d'encarts du doc					ALTER table edtk_index add ED_NBENC integer;
	['ED_ENCPDS', 'INTEGER'],			# poids des encarts du doc					ALTER table edtk_index add ED_ENCPDS INTEGER;
	['ED_BAC_INSERT', 'INTEGER'],			# Appel de bac ou d'insert

	# SECTION EDITION DE L'INDEX
	['ED_TYPED', 'CHAR'],				# type d'édition
	['ED_MODEDI', 'CHAR'],				# mode d'édition
	['ED_FORMATP', 'VARCHAR2(2)'],		# format papier
	['ED_PGORIEN', 'VARCHAR2(2)'],		# orientation de l'édition
	['ED_FORMFLUX', 'VARCHAR2(3)'],		# format du flux d'édition
#	['ED_FORMDEF', 'VARCHAR2(8)'],		# Formdef AFP
#	['ED_PAGEDEF', 'VARCHAR2(8)'],		# Pagedef AFP
#	['ED_FORMS', 'VARCHAR2(8)'],			# Forms 

	# SECTION PLI DE L'INDEX
	['ED_IDPLI', 'INTEGER'],				# identifiant du pli
	['ED_NBDOCPLI', 'INTEGER NOT NULL'],	# nombre de documents du pli
	['ED_NUMPGPLI', 'INTEGER NOT NULL'],	# numéro de la page (face) dans le pli
	['ED_NBPGPLI', 'INTEGER'],			# nombre de pages (faces) du pli
	['ED_NBFPLI', 'INTEGER'],			# nombre de feuillets du pli
	['ED_LISTEREFENC', 'VARCHAR2(64)'],	# liste des encarts du pli
	['ED_PDSPLI', 'INTEGER'],			# poids du pli en mg
	['ED_TYPOBJ', 'CHAR'],				# type d'objet dans le pli	xxxxxx  conserver ?
	['ED_DTPOSTE', 'VARCHAR2(8)'],		# status de lotissement (date de remise en poste ou status en fonction des versions)  ALTER TABLE edtk_index rename ED_DTPOSTE to ED_STATUS VARCHAR2(8);
);


sub create_table_PARA {
	my $dbh = shift;
	my $table = "EDTK_TEST_PARA";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_PARA_REFIDDOC VARCHAR2(20) NOT NULL"; 
	$sql .= ", ED_PARA_CORP VARCHAR2(8) NOT NULL";	# Entity related to the document
	$sql .= ", ED_ID INTEGER NOT NULL";			#
	$sql .= ", ED_TSTAMP VARCHAR2(14) NOT NULL";		# Timestamp of event
	$sql .= ", ED_TEXTBLOC VARCHAR2(512)";
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}

sub create_table_DATAGROUPS {
	my $dbh = shift;
	my $table = "EDTK_TEST_DATAGROUPS";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_DGPS_REFIDDOC VARCHAR2(20) NOT NULL"; 
	$sql .= ", ED_ID INTEGER NOT NULL";
	$sql .= ", ED_DATA VARCHAR2(64)";
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_ACQUIT {
	my $dbh = shift;
	my $table = "EDTK_ACQ";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_SEQLOT  VARCHAR2(7)  NOT NULL";	# identifiant du lot de mise sous plis (sous-lot)
	$sql .= ", ED_LOTNAME VARCHAR2(16) NOT NULL";	# alter table EDTK_LOTS add ED_LOTNAME VARCHAR2(16);  alter table EDTK_LOTS modify ED_LOTNAME VARCHAR2(16) NOT NULL;
	$sql .= ", ED_DTPRINT VARCHAR2(8)";			# date de d'imrpession
	$sql .= ", ED_DTPOST  VARCHAR2(8)  NOT NULL";	# date de remise en poste
	$sql .= ", ED_NBPGLOT INTEGER   NOT NULL";		# nombre de documents du pli
	$sql .= ", ED_NBPLISLOT INTEGER NOT NULL";		# nombre de documents du pli
	$sql .= ", ED_DTPOST2 VARCHAR2(8)";			# date de remise en poste		
	$sql .= ", ED_DTCHECK VARCHAR2(8)";			# date de check
	$sql .= ", ED_STATUS VARCHAR2(4)";				# check status
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_INDEX {
	my ($dbh, $table) = @_;

	my $sql = "CREATE TABLE $table (" .
	    join(', ', map {"$$_[0] $$_[1]"} @INDEX_COLS) . ", " .
	    "PRIMARY KEY (ED_IDLDOC, ED_SEQDOC, ED_IDSEQPG)" .
	")";

	$dbh->do(_sql_fixup($dbh, $sql)) or warn "WARN : " . $dbh->errstr . "\n";
}

sub create_lot_sequence {
	my $dbh = shift;

	$dbh->do('CREATE SEQUENCE EDTK_IDLOT MINVALUE 0 MAXVALUE 999 CYCLE');
}


sub create_SCHEMA {
	my ($dbh, $table, $maxkeys) = @_;
	my $cfg = config_read('EDTK_DB');

	create_lot_sequence($dbh);
	create_table_INDEX($dbh, $cfg->{'EDTK_DBI_OUTMNGR'});
	$dbh->do('CREATE INDEX ed_seqlot_idx ON EDTK_INDEX (ed_seqlot)');
	create_table_TRACKING($dbh, $cfg->{'EDTK_DBI_TRACKING'}, $cfg->{'EDTK_MAX_USER_KEY'});
		
	create_table_ACQUIT($dbh);
	create_table_FILIERES($dbh);
	create_table_LOTS($dbh);
	create_table_REFIDDOC($dbh);
	create_table_SUPPORTS($dbh);
}


sub _sql_fixup {
	my ($dbh, $sql) = @_;

	if ($dbh->{'Driver'}->{'Name'} ne 'Oracle') {
		$sql =~ s/VARCHAR2 *(\(\d+\))/VARCHAR$1/g;
	}
	return $sql;
}

1;
