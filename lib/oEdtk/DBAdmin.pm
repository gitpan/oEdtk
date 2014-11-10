package oEdtk::DBAdmin;

use DBI;
use oEdtk::Config	qw(config_read);
use Text::CSV;
use strict;
use warnings;

use Exporter;

our $VERSION		= 0.24;
our @ISA			= qw(Exporter);
our @EXPORT_OK		= qw(
				csv_import
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
				db_connect
				historicize_table
				move_table
				@INDEX_COLS
				);


sub csv_import ($$$;$){
	# insertion d'un fichier csv dans une table
	# csv_import($dbh, "EDTK_ACQ", $ARGV[0], 
	#		{sep_char => ',' ,					# ',' is default value
	#		quote_char => '"',					# '"' is default value
	#		header => 'ED_SEQLOT,ED_LOTNAME,...'},	# default value, no header, read header from csv file
	# 		mode => 'merge');					# 'insert' is default value

###### VERSION ORACLE DU MERGE, DIFF�RENTE DE CELLE DE POSTGRESQL
	#MERGE INTO table_name USING table_reference ON (condition)
	#  WHEN MATCHED THEN
	#  UPDATE SET column1 = value1 [, column2 = value2 ...]
	#  WHEN NOT MATCHED THEN
	#  INSERT (column1 [, column2 ...]) VALUES (value1 [, value2 ...

	#MERGE INTO Table1 T1
	#  USING (SELECT Id, Meschamps FROM Table2) T2
	#    ON ( T1.Id = T2.Id ) -- Condition de correspondance
	#WHEN MATCHED THEN -- Si Vraie
	#  UPDATE SET T1.Meschamps = T2.Meschamps
	#WHEN NOT MATCHED THEN -- Si faux
	#  INSERT (T1.ID, T1.MesChamps) VALUES ( T2.ID, T2.MesChamps);

###### VERSION POSTGRESQL
	#MERGE INTO table [[AS] alias]
	#USING [table-ref | query]
	#ON join-condition
	#[WHEN MATCHED [AND condition] THEN MergeUpdate | DELETE | DO NOTHING | RAISE ERROR]
	#[WHEN NOT MATCHED [AND condition] THEN MergeInsert | DO NOTHING | RAISE ERROR]
	#MergeUpdate is
	#
	#UPDATE SET { column = { expression | DEFAULT } |
	#( column [, ...] ) = ( { expression | DEFAULT } [, ...] ) }
	#[, ...]
	#(yes, there is no WHERE clause here)
	#MergeInsert is
	#INSERT [ ( column [, ...] ) ]
	#{ DEFAULT VALUES | VALUES ( { expression | DEFAULT } [, ...] )
	#[, ...]} 

	my ($dbh, $table, $in, $params) = @_;
	$params->{'mode'}		= $params->{'mode'} || "insert";
	$params->{'sep_char'} 	= $params->{'sep_char'} || ",";
	$params->{'quote_char'}	= $params->{'quote_char'}||'"' ;
	
	open(my $fh, '<', $in) or die "Cannot open index file \"$in\": $!\n";
	my $csv = Text::CSV->new({ binary => 1, sep_char => $params->{'sep_char'}, 
							quote_char => $params->{'quote_char'}});

	my $line;
	if (defined $params->{'header'}){
		$line = $params->{'header'};
	} else {
		$line = <$fh>;
	}
	$csv->parse($line);
	my @cols = $csv->fields();

	while (<$fh>) {
		$csv->parse($_);
		my @data = $csv->fields();

		# s'assurer qu'on ins�re pas des valeurs null (contraintes ???) ou pas ?
		for (my $i=0 ; $i<=$#data ; $i++ ){
			$data[$i]=$data[$i] || "";
		}
		my ($sql, $seqlot);
		
		if 	($params->{'mode'}=~/merge/i) {
			$sql = "SELECT " . $cols[0] . " FROM " . $table 
				. " WHERE " . $cols[0] . " =?  ";
			my $sth = $dbh->prepare_cached($sql);
			$sth->execute($data[0]);

			$seqlot = $sth->fetchrow_hashref();
		}
		
		if (defined $seqlot->{'ED_SEQLOT'}) {
			$sql = "UPDATE " . $table . " SET " . join ('=? , ', @cols) . "=? "
				. " WHERE " . $cols[0] . " =?  ";
			my $sth = $dbh->prepare_cached($sql);
			$sth->execute(@data, $data[0]);
		
		} else {
			$sql = "INSERT INTO " . $table . " (" . join(',', @cols)
				. ") VALUES (" . join(',', ('?') x @cols) . ")";
			my $sth = $dbh->prepare_cached($sql);
			$sth->execute(@data);
		}

	}
	close($fh);
}


sub _db_connect1 {
	my ($cfg, $dsnvar, $dbargs) = @_;
	my $dbh;
	my $dsn = $cfg->{$dsnvar};

	warn "INFO : Connecting to DSN $dsn, $dsnvar...\n";

	# gestion de la connexion dans une boucle temporis�e, pour effectuer 3 tentatives de connexion avec incr�ment de pause
	for (my $i=0;$i<3;$i++){
		sleep ($cfg->{EDTK_WAITRUN}*$i);
		eval {
			 $dbh=DBI->connect($dsn, $cfg->{"${dsnvar}_USER"}, $cfg->{"${dsnvar}_PASS"}, $dbargs); ## xxxx
		};

		if ($@){
			# en cas d'incident de connexion, on ne dit rien, on essaie encore
			warn "INFO : DBI connection missmatch to $dsnvar, we try 3 times\n";
			warn "INFO : error message was : $@\n";

		} else {
			# si �a semble bon on sort
			$i=4;
		}
	}
	return $dbh;	
}

 
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
		if (defined $cfg->{"${dsnvar}_BAK"}) { # il faudrait ajouter le param�trage dans la base de backup (proc�dure de cr�ation de cette base)
			warn "ERROR: Could not connect to main database server: $DBI::errstr\n";
			$dbh = _db_connect1($cfg, "${dsnvar}_BAK", $dbargs);
			if (!defined $dbh) {
				die "ERROR: Could not connect to backup database server : $DBI::errstr\n";
			}
		} else {
			die "ERROR: Could not connect to database server : $DBI::errstr\n";
		}
	}
	return $dbh;
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
#	$sql .= ", PRIMARY KEY (ED_SNGL_ID, ED_JOB_EVT, ED_APP)"
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
	$sql .= "( ED_IDFILIERE VARCHAR2(5) NOT NULL";	# rendre UNIQUE filiere id   ALTER table edtk_filieres modify ED_IDFILIERE VARCHAR2(5) NOT NULL;
	$sql .= ", ED_IDMANUFACT VARCHAR2(16)";	  
	$sql .= ", ED_DESIGNATION VARCHAR2(64)";		# 
	$sql .= ", ED_ACTIF CHAR NOT NULL";			# Flag indiquant si la filiere est active ou pas 
	$sql .= ", ED_PRIORITE INTEGER UNIQUE";			# rendre UNIQUE Ordre d'execution des filieres ALTER table edtk_filieres modify  ED_PRIORITE INTEGER UNIQUE; 
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
#	$sql .= ", PRIMARY KEY (ED_IDFILIERE, ED_IDMANUFACT, ED_PRIORITE)"
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_LOTS {
	my $dbh = shift;
	my $table = "EDTK_LOTS";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_IDLOT VARCHAR2(8)  NOT NULL";		# rendre UNIQUE 
	$sql .= ", ED_PRIORITE INTEGER   UNIQUE"; 		# rendre UNIQUE 	ALTER table EDTK_LOTS modify ED_PRIORITE INTEGER UNIQUE;
	$sql .= ", ED_IDAPPDOC VARCHAR2(20) NOT NULL";	# renommer en ed_refiddoc ATTENTION cf structure index.xls
	$sql .= ", ED_CPDEST VARCHAR2(8)"; 			# alter table EDTK_LOTS modify ED_CPDEST VARCHAR2(8);
	$sql .= ", ED_FILTER VARCHAR2(64)";			# alter table EDTK_LOTS add ED_FILTER VARCHAR2(64); 
	$sql .= ", ED_GROUPBY VARCHAR2(16)"; 
	$sql .= ", ED_IDMANUFACT VARCHAR2(16) NOT NULL"; 
	$sql .= ", ED_LOTNAME VARCHAR2(16) NOT NULL";	# alter table EDTK_LOTS modify ED_LOTNAME VARCHAR2(16) NOT NULL;
	$sql .= ", ED_IDGPLOT VARCHAR2(16) NOT NULL";	
	$sql .= ", ED_REFENC VARCHAR2(20) ";			# a mettre en place pour ajouter des encarts sp�cifiques � certains lots (cf impact calcul lotissement) # alter table EDTK_LOTS add ED_REFENC VARCHAR2(20)
#	$sql .= ", PRIMARY KEY (ED_IDLOT, ED_PRIORITE, ED_IDAPPDOC)"
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
#	$sql .= ", PRIMARY KEY (ED_REFIDDOC, ED_CORP, ED_CATDOC)"
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_SUPPORTS {
	my $dbh = shift;
	my $table = "EDTK_SUPPORTS";

	my $sql = "CREATE TABLE $table";
	$sql .= "( ED_REFIMP VARCHAR2(16) UNIQUE"; 	# ALTER table EDTK_SUPPORTS modify ED_REFIMP VARCHAR2(16) UNIQUE;
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
#	$sql .= ", PRIMARY KEY (ED_REFIMP, ED_TYPIMP)"
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


our @INDEX_COLS = (
	# SECTION COMPOSITION DE L'INDEX
	['ED_REFIDDOC','VARCHAR2(20) NOT NULL'],# identifiant dans le r�f�rentiel de document
	['ED_IDLDOC',	'VARCHAR2(17) NOT NULL'],# Identifiant du document dans le lot de mise en page ED_SNGL_ID
	['ED_IDSEQPG',	'INTEGER NOT NULL'],	# Sequence Num�ro de s�quence de page dans le lot de mise en page
	['ED_SEQDOC',	'INTEGER NOT NULL'],	# Num�ro de s�quence du document dans le lot

	['ED_CPDEST',	'VARCHAR2(8)'],		# Code postal Destinataire
	['ED_VILLDEST','VARCHAR2(30)'],		# Ville destinataire				ALTER table edtk_index modify ED_VILLDEST VARCHAR2(30);
	['ED_IDDEST',	'VARCHAR2(25)'],		# Identifiant du destinataire dans le syst�me de gestion
	['ED_NOMDEST',	'VARCHAR2(38)'],		# Nom destinataire					ALTER table edtk_index modify ED_NOMDEST VARCHAR2(38);
	['ED_IDEMET',	'VARCHAR2(10)'],		# identifiant de l'�metteur
	['ED_DTEDTION','VARCHAR2(8) NOT NULL'], # date d'�dition, celle qui figure sur le document
	['ED_TYPPROD',	'CHAR'],				# type de production associ�e au lot
	['ED_PORTADR',	'CHAR'],				# indicateur de document porte adresse
	['ED_ADRLN1',	'VARCHAR2(38)'],		# ligne d'adresse 1
	['ED_CLEGED1',	'VARCHAR2(20)'],		# clef pour syst�me d'archivage
	['ED_ADRLN2',	'VARCHAR2(38)'],		# ligne d'adresse 2
	['ED_CLEGED2',	'VARCHAR2(20)'],		# clef pour syst�me d'archivage
	['ED_ADRLN3',	'VARCHAR2(38)'],		# ligne d'adresse 3
	['ED_CLEGED3',	'VARCHAR2(20)'],		# clef pour syst�me d'archivage
	['ED_ADRLN4',	'VARCHAR2(38)'],		# ligne d'adresse 4
	['ED_CLEGED4',	'VARCHAR2(20)'],		# clef pour syst�me d'archivage
	['ED_ADRLN5',	'VARCHAR2(38)'],		# ligne d'adresse 5
	['ED_CORP',	'VARCHAR2(8)  NOT NULL'],# soci�t� �mettrice de la page		ALTER table edtk_index modify ED_CORP VARCHAR2(8) NOT NULL;
	['ED_DOCLIB',	'VARCHAR2(32)' ],		# merge library compuset associ�e ? la page
	['ED_REFIMP',	'VARCHAR2(8)'],		# r�f�rence de pr?-imprim? ou d'imprim? ou d'encart
	['ED_ADRLN6',	'VARCHAR2(38)'],		# ligne d'adresse 6
	['ED_SOURCE',	'VARCHAR2(8) NOT NULL'],	# Source de l'index
	['ED_OWNER',	'VARCHAR2(10)'],		# propri�taire du document (utilisation en gestion / archivage de documents)
	['ED_HOST',	'VARCHAR2(32)'],		# Hostname de la machine d'ou origine cette entr�e
	['ED_IDIDX',	'VARCHAR2(7) NOT NULL'],	# identifiant de l'index
	['ED_CATDOC',	'CHAR'],				# cat�gorie de document
	['ED_CODRUPT',	'VARCHAR2(8)'],		# code for�age de rupture	ALTER table edtk_index modify ED_CODRUPT VARCHAR2(8);

	# SECTION LOTISSEMENT DE L'INDEX
	['ED_IDLOT',	'VARCHAR2(6)'],		# identifiant du lot
	['ED_SEQLOT',	'VARCHAR2(7)'],		# identifiant du lot de mise sous plis (sous-lot) ALTER table edtk_index modify ED_SEQLOT VARCHAR2(7);
	['ED_DTLOT',	'VARCHAR2(8)'],		# date de la cr�ation du lot de mise sous plis
	['ED_IDFILIERE','VARCHAR2(5)'],		# identifiant de la fili�re de production     	ALTER table edtk_index modify ED_IDFILIERE VARCHAR2(5);
	['ED_SEQPGDOC','INTEGER'],			# num�ro de s�quence de page dans le document
	['ED_NBPGDOC',	'INTEGER'],			# nombre de page (faces) du document
	['ED_POIDSUNIT','INTEGER'],			# poids de l'imprim? ou de l'encart en mg
	['ED_NBENC',	'INTEGER'],			# nombre d'encarts du doc					ALTER table edtk_index add ED_NBENC integer;
	['ED_ENCPDS',	'INTEGER'],			# poids des encarts du doc					ALTER table edtk_index add ED_ENCPDS INTEGER;
	['ED_BAC_INSERT','INTEGER'],			# Appel de bac ou d'insert

	# SECTION EDITION DE L'INDEX
	['ED_TYPED',	'CHAR'],				# type d'�dition
	['ED_MODEDI',	'CHAR'],				# mode d'�dition
	['ED_FORMATP',	'VARCHAR2(2)'],		# format papier
	['ED_PGORIEN',	'VARCHAR2(2)'],		# orientation de l'�dition
	['ED_FORMFLUX','VARCHAR2(3)'],		# format du flux d'�dition
#	['ED_FORMDEF', 'VARCHAR2(8)'],		# Formdef AFP
#	['ED_PAGEDEF', 'VARCHAR2(8)'],		# Pagedef AFP
#	['ED_FORMS',	'VARCHAR2(8)'],		# Forms 

	# SECTION PLI DE L'INDEX
	['ED_IDPLI',	'INTEGER'],				# identifiant du pli
	['ED_NBDOCPLI','INTEGER NOT NULL'],	# nombre de documents du pli
	['ED_NUMPGPLI','INTEGER NOT NULL'],	# num�ro de la page (face) dans le pli
	['ED_NBPGPLI',	'INTEGER'],			# nombre de pages (faces) du pli
	['ED_NBFPLI',	'INTEGER'],			# nombre de feuillets du pli
	['ED_LISTEREFENC','VARCHAR2(64)'],		# liste des encarts du pli
	['ED_PDSPLI',	'INTEGER'],			# poids du pli en mg
	['ED_TYPOBJ',	'CHAR'],				# type d'objet dans le pli	xxxxxx  conserver ?
	['ED_STATUS',	'VARCHAR2(8)'],		# status de lotissement (date de remise en poste ou status en fonction des versions)  # ALTER TABLE EDTK_INDEX ADD ED_STATUS VARCHAR2(8);  # attention tr�s lourd a �x�cuter ne pas faire en prod : UPDATE EDTK_INDEX SET ED_STATUS = ED_DTPOSTE;
	['ED_DTPOSTE',	'VARCHAR2(8)']			# � supprimer : status de lotissement (date de remise en poste ou status en fonction des versions)  ALTER TABLE edtk_index rename ED_DTPOSTE to ED_STATUS VARCHAR2(8);

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
#	$sql .= ", PRIMARY KEY (ED_PARA_REFIDDOC, ED_PARA_CORP)"
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
	$sql .= ", ED_NBFACES INTEGER   	NOT NULL";	# nombre de faces du lot (faces comptables, comprenant les faces blanches de R�/V�)
	$sql .= ", ED_NBPLIS INTEGER 		NOT NULL";	# nombre de documents du pli
	$sql .= ", ED_DTPOST2 VARCHAR2(8)";			# date de remise en poste		
	$sql .= ", ED_DTCHECK VARCHAR2(8)";			# date de check
	$sql .= ", ED_STATUS VARCHAR2(4)";				# check status
#	$sql .= ", PRIMARY KEY (ED_SEQLOT, ED_LOTNAME)"
	$sql .= ")";

	$dbh->do(_sql_fixup($dbh, $sql)) or die $dbh->errstr;
}


sub create_table_INDEX {
	my ($dbh, $table) = @_;

	my $sql	= "CREATE TABLE $table ("
			. join(', ', map {"$$_[0] $$_[1]"} @INDEX_COLS) . ", "
			. " PRIMARY KEY (ED_IDLDOC, ED_SEQDOC, ED_IDSEQPG)"	# rajouter ED_SEQLOT ?
			. ")";

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
	# v�rifier les propositions de cl�s primaires et les index (attention � ne pas faire n'importe quoi)
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
#
#
#10g SOC5> SELECT *
#  2  FROM v$version;
# 
#BANNER
#----------------------------------------------------------------
#Oracle DATABASE 10g Enterprise Edition Release 10.1.0.3.0 - Prod
#PL/SQL Release 10.1.0.3.0 - Production
#CORE    10.1.0.3.0      Production
#TNS FOR 32-bit Windows: Version 10.1.0.3.0 - Production
#NLSRTL Version 10.1.0.3.0 - Production
# 
#5 ligne(s) s�lectionn�e(s).
# 
#10g SOC5> DESC dvp
# Nom                            NULL ?    Type
# ------------------------------- -------- ----
# COL_NUM                                  NUMBER(12)
# 
#10g SOC5> SELECT *
#  2  FROM dvp;
# 
#   COL_NUM
#----------
#        10
#        12
#   1000000
#   5923146
# 
#4 ligne(s) s�lectionn�e(s).
# 
#10g SOC5> ALTER TABLE dvp RENAME COLUMN col_num TO col_renommee;
# 
#TABLE modifi�e.
# 
#10g SOC5> DESC dvp
# Nom                            NULL ?    Type
# ------------------------------- -------- ----
# COL_RENOMMEE                             NUMBER(12)
#