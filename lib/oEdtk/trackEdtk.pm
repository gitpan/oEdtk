package oEdtk::trackEdtk;

BEGIN {
		use oEdtk::prodEdtk		0.42;
		use Config::IniFiles;
		use Sys::Hostname;
		use Digest::MD5 			qw(md5_base64);
		use DBI;
		use strict;

		use Exporter;
		use vars 	qw($VERSION @ISA  @EXPORT_OK); # @EXPORT %EXPORT_TAGS);
	
		$VERSION		= 0.0030;
		@ISA			= qw(Exporter);
#		@EXPORT		= qw(
#						);

		@EXPORT_OK	= qw(
						ini_Edtk_Conf 		conf_To_Env 
						env_Var_Completion

						init_Tracking 		track_Obj
						define_Mod_Ed		define_Job_Evt
						define_Track_Key 

						edit_Track_Table
						create_Track_Table	prepare_Tracking_Env
						drop_Track_Table
						)

	}

	# 3 m�thodes possibles d'alimentation (config edtk.ini -> EDTK_TRACK_MODE) :
	# -1- DB  : suivi directement dans un SGBD (DB)-> ralentissement du traitement de prod (ins�rer les info de suivi en fin de traitement pour limiter l'impact => END du module ?)
	# -2- FDB : suivi via SQLite -> pas de gestion de plusieurs acc�s en temps r�el => cr�er 1 fichier db par process (procDB)-> organiser une consolidation des donn�es 
	# -3- LOG : fichiers de suivi � plat -> organiser une consolidation des donn�es
	#
	# ? A VOIR : bug dans la cr�ation dynamique du fichier SQLite, on utilise pas le TSTAMP/PROCESS_ID ???

	my $DBI_DNS	="";
	my $DBI_USER	="" ;
	my $DBI_PASS	="" ;
	my $TABLENAME	="tracking_oEdtk";

	my $ED_HOST;
	my $ED_TSTAMP;
	my $ED_PROC;
	my $ED_SNGL_ID;
	my $ED_USER;
	my $ED_SEQ;
	my $ED_APP;
	my $ED_MOD_ED;
	my $ED_JOB_EVT;
	my $ED_OBJS;
	my @ED_K_NAME;
	my @ED_K_VAL;

	my @TRACKED_OBJ;
	my @DB_COL_NAME;

	my $NOK=-1;


sub ini_Edtk_Conf {
	# recherche du fichier de configuration
	# renvoi le chemin au fichier de configuation valide
	my $iniEdtk 	=$INC{'oEdtk/trackEdtk.pm'};
	$iniEdtk		=~s/(trackEdtk\.pm)//;
	$iniEdtk 		.="iniEdtk/edtk.ini";
	my $hostname	=uc ( hostname());

	# OUVERTURE DU FICHIER DE CONFIGURATION
	my $tmpIniEdtk	=$iniEdtk;
	my $confIni;
	while ($tmpIniEdtk ne 'local'){
		if (! (-e $tmpIniEdtk)){die "ERR. config file not found : $tmpIniEdtk\n";}
			$confIni	= Config::IniFiles->new( -file => $tmpIniEdtk, -default => 'DEFAULT');

			$iniEdtk	=$tmpIniEdtk;
			# recherche de la variable iniEdtk dans la section '$hostname' ou par d�faut
			#  dans la section 'DEFAULT' (cf m�thode new)
			$tmpIniEdtk=$confIni->val( $hostname, 'iniEdtk' );

		# si iniEdtk == fichier courant alors mettre la valeur � local (�viter les boucle infinies)
		if ($tmpIniEdtk eq $iniEdtk) { last; }
	}

	$ENV{EDTK_INIEDTK}	=$iniEdtk;		
return $iniEdtk;
}


sub conf_To_Env ($;$) {
	# charge les sections demand�es du fic de config dans la configuration d'environnement
	# en param, passer le chemin d'acc�s au fichier ini + la section � charger
	# si la section HOSTNAME existe elle surcharge les valeurs de la section
	my $confIni=shift;
	my $section=shift;
	$section ||='DEFAULT';
	
	if (-e $confIni){
	} else {
		die "ERR. config file not found : $confIni\n";
	}

	my $hostname	=uc ( hostname());
	#my $osName=$^O;
	#if ($osName eq "MSWin32"){
	#	$HOSTNAME=$ENV{COMPUTERNAME};
	#} else {
	#	$HOSTNAME=hostname();
	#	print "Cas OS <> MSWin32, d�finir HOSTNAME $HOSTNAME\n";# use Sys::Hostname; ?
	#}

	# OUVERTURE DU FICHIER DE CONFIGURATION
	my %hConfIni;
	tie %hConfIni, 'Config::IniFiles',( -file => $confIni );

	# CHARGEMENT DES VALEURS DE LA SECTION
	my %hSection;
 	if (exists $hConfIni{$section}) {
		%hSection =%{$hConfIni{$section}};
	}

	# CHARGEMENT EN SURCHARGE DES VALEURS PROPRES AU HOSTNAME
	my %hHostname;
	if (exists $hConfIni{$hostname}) {
		undef %hSpecific;
		%hHostname =%{$hConfIni{$hostname}};
	} else {
		warn "INFO machine '$hostname' inconnue dans la configuration";
	}
 	%hConfig=(%hSection,%hHostname);
 
 	$0=~/([\w\.\-]+)\\\w+\.\w+$/;
	# D�FINITION POUR L'ENVIRONNEMENT DE D�V DE L'APPLICATION/PROGRAMME COURANT
	$hConfig{'EDTK_PRGNAME'} =$1;
	$hConfig{'EDTK_OPTJOB'}	=$EDTK_OPTJOB;

	# mise en place des variables d'environnement
	while ((my $cle, my $valeur) = each (%hConfig)){
		$valeur ||="";
		$ENV{$cle}=$valeur;
	}
1;
}


sub env_Var_Completion (\$){
	# d�veloppe les chemins en rempla�ant les variables d'environnement par les valeurs r�elles
	# tous les niveaux d'imbrication d�finis dans les variables d'environnement sont d�velopp�s
	# n�cessite au pr�alable que les variables d'environnements soient d�finies
	my $rScript =shift;
	if ($^O eq "MSWin32"){
		# il peut y avoir des variables dans les les variables d'environnement elles m�mes
		while (${$rScript}=~/\$/g) {
			${$rScript}=~s/\$(\w+)/${ENV{$1}}/g;
		}
		${$rScript}=~s/(\/)/\\/g;

	} else {
		# verifier compatibilit� sous *nix
	}
1;
}


# PARTIE SUIVI DE PRODUCTION

	my $DBH;
	my %h_subInsert;
	$h_subInsert{'LOG'}=\&subInsert_Log;
	$h_subInsert{'DB'} =\&subInsert_DB;
	$h_subInsert{'FDB'}=\&subInsert_DB;
	$h_subInsert{'none'}=\&noSub;

	my %h_subClose;
	$h_subClose{'DB'} =\&subClose_DB;
	$h_subClose{'FDB'}=\&subClose_DB;


sub prepare_Tracking_Env() {
	my $iniEdtk	=ini_Edtk_Conf();
	conf_To_Env($iniEdtk, 'ENVDESC');
	conf_To_Env($iniEdtk, 'APPEDTK');
	conf_To_Env($iniEdtk, 'TRACKING');
	maj_sans_accents($ENV{EDTK_TRACK_MODE});

1;
}

sub open_Tracking_Env(){
	if ($ENV{EDTK_TRACK_MODE} =~/FDB/i){
		# DB File nowTime/process
		$ENV{EDTK_DBI_DNS}=~s/(.+)\.(\w+)$/$1\.$ED_TSTAMP\.$ED_PROC\.$2/;
		warn "INFO tracking to $ENV{EDTK_DBI_DNS}\n";
		create_Track_Table();
		open_DBI();
			
	} elsif ($ENV{EDTK_TRACK_MODE} =~/LOG/i){
		# log

	} elsif ($ENV{EDTK_TRACK_MODE} =~/DB/i){
		# DB connexion tracking
		open_DBI();

	} else {
		$ENV{EDTK_TRACK_MODE} = "none";
		
	}

	if (!($h_subInsert{$ENV{EDTK_TRACK_MODE}}) && !($h_subCreate{$ENV{EDTK_TRACK_MODE}})){
		warn "INFO $ENV{EDTK_TRACK_MODE} undefined - tracking halted\n";
		$ENV{EDTK_TRACK_MODE} ="none";
	}

1;
}

sub open_DBI(){
	my $dbargs = {	AutoCommit => $ENV{EDTK_DBI_AutoCommit},
				RaiseError => $ENV{EDTK_DBI_RaiseError},
				PrintError => $ENV{EDTK_DBI_PrintError}};
	$DBH = DBI->connect($ENV{EDTK_DBI_DNS},
					$ENV{EDTK_DBI_USER},
					$ENV{EDTK_DBI_PASS},
					$dbargs)
			or die "ERR no connexion to $ENV{DBI_DSN} " . DBI->errstr;

1;
}


sub init_Tracking(;@){
	my $Mod_Ed	=shift;
	my $Typ_Job	=shift;
	my $Job_User	=shift;
	my @Track_Key	=@_;
	define_Mod_Ed	($Mod_Ed);	# 'Undef' by default 
	define_Job_Evt ($Typ_Job);	# 'Spool' by default
	define_Job_User($Job_User);	# job request user, by default 'Undef'
	$ED_HOST		=hostname();
	$ED_TSTAMP	=nowTime();
	$ED_PROC		=$$;
	$ED_SEQ		=0;			# (dynamic, private)
	$ED_SNGL_ID	= md5_base64($ED_HOST.$ED_TSTAMP.$ED_PROC);

	&prepare_Tracking_Env();
	&open_Tracking_Env();
	
	my $indice =0;
	foreach my $element (@Track_Key) {
		define_Track_Key($element, $indice++);	# default key for indiced col_name
	}

	$0 =~/([\w-]+)[\.plmex]*$/;
	$1 ? $ED_APP ="application" : $ED_APP =$1;

	$ED_OBJS		=1;		## default insert unit count (dynamic)
	#@ED_K_VAL	="";		## (dynamic)

	warn "INFO tracking init ( track mode : $ENV{EDTK_TRACK_MODE}, edition mode : $ED_MOD_ED, job type : $ED_JOB_EVT, user : $ED_USER, optional Keys : @ED_K_NAME )\n";

return $ED_SNGL_ID;
}


sub track_Obj (;@){
	# track_Obj ([$ED_OBJS, $ED_JOB_EVT, @ED_K_VAL])
	#  $ED_OBJS (optionel) : nombre d'unit� de l'objet (1 par defaut)
	#  $ED_JOB_EVT (optio) : evenement en question (cf define_Job_Evt)
	#  @ED_K_VAL(optionel) : valeurs des clefs optionnels d�finies avec init_Tracking (m�me ordre)

	$ED_SEQ++;
	$ED_OBJS 		=shift;
	$ED_OBJS		||=1;
	define_Job_Evt (shift);
	@ED_K_VAL =@_;

	undef @TRACKED_OBJ;
	push (@TRACKED_OBJ, nowTime());
	push (@TRACKED_OBJ, $ED_USER);
	push (@TRACKED_OBJ, $ED_SEQ);
#	push (@TRACKED_OBJ, $ED_PROC);
	push (@TRACKED_OBJ, $ED_SNGL_ID);
	push (@TRACKED_OBJ, $ED_APP);
	push (@TRACKED_OBJ, $ED_MOD_ED);

	push (@TRACKED_OBJ, $ED_JOB_EVT);
	push (@TRACKED_OBJ, $ED_OBJS);
	undef @DB_COL_NAME;
	for (my $i=0 ; $i le $#ED_K_VAL ; $i++) {
		push (@TRACKED_OBJ, $ED_K_NAME[$i]);
		push (@TRACKED_OBJ, $ED_K_VAL[$i]);
		push (@DB_COL_NAME, "ED_K${i}_NAME");
		push (@DB_COL_NAME, "ED_K${i}_VAL");
	}
	
	&{$h_subInsert{$ENV{EDTK_TRACK_MODE}}}
		or die "ERR. undefined EDTK_TRACK_MODE -> $ENV{EDTK_TRACK_MODE}\n";
1;
}


sub define_Mod_Ed ($) {
	# Printing Mode : looking for one of the following :
	#	 Undef (default), Batch, Tp, Web, Mail
	my $value	 =shift;

	if ($value) { $ED_MOD_ED =$value }; 
	$ED_MOD_ED	=~ /([NBTWM])/;
	$ED_MOD_ED	=$1;
	$ED_MOD_ED	||="U"; 	# Undef by default

return $ED_MOD_ED;
}


sub define_Job_Evt ($) {
	# Job Event : looking for one of the following : 
	#	 Job (default), Spool, Document, Line, Warning, Error
	my $value	 =shift;

	if ($value) { $ED_JOB_EVT =$value };
	$ED_JOB_EVT	=~ /([JSDLWE])/;
	$ED_JOB_EVT	=$1;
	$ED_JOB_EVT	||="J"; 	# Job by default

return $ED_JOB_EVT;
}


sub define_Job_User ($) {
	# job request user : looking for one of the following :
	#	 Undef (default), user Id (max 10 alphanumerics)
	my $value	 =shift;
	$ED_USER	||="Undef"; 	# Undef by default

	if ($value) { $ED_USER =$value }; 
	$ED_USER	=~ /(\w{1,10})/;
	$ED_USER	=$1;

return $ED_USER;
}


sub define_Track_Key ($;$) {
	# to define the col_name of the n indiced tracking key
	my $value	 =shift;
	my $indice =shift;
	$indice 	||=0;

	if (!defined $ENV{EDTK_MAX_USER_KEY}) {	
		warn "WARN : tracking key undefined\n";
		return 0;

	} elsif ($indice gt ($ENV{EDTK_MAX_USER_KEY}-1)) { 
		warn "WARN : tracking key not allowed (limit is $ENV{EDTK_MAX_USER_KEY})\n";
		return 0;
	}
	if ($value) { $ED_K_NAME[$indice] =$value; }

	$ED_K_NAME[$indice] =~ s/\s/\_/g;
	maj_sans_accents($ED_K_NAME[$indice]);

return $ED_K_NAME[$indice];
}


sub subInsert_Log(){
	# dans le cas d'un suivi sous forme de fichiers log
	# � compl�ter avec l'utisation du rempla�ant du Logger

	my $request	=join (", ", @TRACKED_OBJ);
	warn "$request\n";

1;
}


sub subInsert_DB() {
	# constructuction de la commande SQL pour insertion dans une base DBI (file/DB)

	my $request="insert into $ENV{EDTK_DBI_TABLENAME}"; 
	$request	.=" (";
	$request	.="ED_TSTAMP, ED_USER, ED_SEQ, ED_SNGL_ID, ED_APP, ED_MOD_ED, ED_JOB_EVT, ED_OBJ_COUNT, ";
	$request	.=join (", ", @DB_COL_NAME);
	$request	.=" ) values ('";
#	formatage de la date pour les SGBD 
#	$request	.=sprintf ("to_date('%014.f', 'YYYYMMDDHH24MISS'), '", shift @TRACKED_OBJ);
	$request	.=join ("', '", @TRACKED_OBJ);
	$request	.="' )";

#	warn "$request\n";

	$DBH->do($request);
	if ($DBH->err()) {
		warn "INFO ".$DBI::errstr."\n";
	}	

#	$DBH->commit();	# n�cessaire si AutoCommit  vaut 0
#	$DBH->disconnect();
#	if ($DBH->err()) { warn "$DBI::errstr\n"; }
1;
}

sub noSub(){
	# fonction a vide pour les pointeurs de fonction %h_subInsert
	# �viter d'utiliser des tests dans des fonctions r�p�titives
	# faux switch/case
return 1;
}


sub test_exist_table(){
	my $dbargs = {	AutoCommit => $ENV{EDTK_DBI_AutoCommit},
				RaiseError => $ENV{EDTK_DBI_RaiseError},
				PrintError => $ENV{EDTK_DBI_PrintError}};
	$DBH = DBI->connect($ENV{EDTK_DBI_DNS},
					$ENV{EDTK_DBI_USER},
					$ENV{EDTK_DBI_PASS},
					$dbargs)
			or die "ERR no connexion to $ENV{DBI_DSN} " . DBI->errstr;

	my $request="select * from $ENV{EDTK_DBI_TABLENAME}";

	$DBH->do($request);
	if ($DBI::errstr) {
		if ( $DBI::errstr =~/no such table/ ) { 
			$DBH->disconnect();
			return 0;
		}
		warn "INFO ".$DBI::errstr."\n";
		$DBH->disconnect();
		return $NOK; 
	}	
	$DBH->disconnect();

1;
}


sub edit_Track_Table(;$){
	my $request=shift;
	&prepare_Tracking_Env();
	&open_DBI();
	
	my $ref_Tab =&fetchall_DBI($request);
	&edit_All_rTab($ref_Tab);
1;
}


sub create_Track_Table(){
	# CREATE TABLE tablename [IF NOT EXISTS][TEMPORARY] (column1data_type, column2data_type, column3data_type);
	&prepare_Tracking_Env();
	
	my $dbargs = {	AutoCommit => 0,
				RaiseError => 0,
				PrintError => 0 };
	$DBH = DBI->connect($ENV{EDTK_DBI_DNS},
					$ENV{EDTK_DBI_USER},
					$ENV{EDTK_DBI_PASS},
					$dbargs)
			or die "ERR no connexion to $ENV{DBI_DSN} " . DBI->errstr;

	my $struct="CREATE TABLE $ENV{EDTK_DBI_TABLENAME} ";
	$struct .="( ED_TSTAMP NUMBER(14)  NOT NULL";	# interesting for formated date and interval search
#	$struct .="( ED_TSTAMP VARCHAR2(14)  NOT NULL";	# most used
#	$struct .="( ED_TSTAMP DATE  NOT NULL";			# Not compatible
#	$struct .=", ED_HOST VARCHAR2(15) NOT NULL";		# hostname
#	$struct .=", ED_PROC VARCHAR2(6) NOT NULL";		# processus
	$struct .=", ED_USER VARCHAR2(10) NOT NULL";		# job request user 
	$struct .=", ED_SEQ NUMBER(9) NOT NULL";		# sequence
	$struct .=", ED_SNGL_ID VARCHAR2(22) NOT NULL";	# Single ID
	$struct .=", ED_APP VARCHAR2(15) NOT NULL";		# application name
	$struct .=", ED_MOD_ED CHAR";					# mode d'edition (Batch, Tp, Web, Mail)
	$struct .=", ED_JOB_EVT CHAR";				# niveau de l'�v�nement dans le job(Spool, Document, Line, Warning, Error)
	$struct .=", ED_OBJ_COUNT NUMBER(15)";			# nombre d'�l�ments/objets attach�s � l'�v�nement

	for (my $i=0 ; $i lt $ENV{EDTK_MAX_USER_KEY} ; $i++) {
		$struct .=", ED_K${i}_NAME VARCHAR2(5)";	# nom de clef $i
		$struct .=", ED_K${i}_VAL VARCHAR2(30)";	# valeur clef $i
	}
	$struct .=")"; #, CONSTRAINT pk_$ENV{EDTK_DBI_TABLENAME} PRIMARY KEY (ED_TSTAMP, ED_PROC, ED_SEQ)";

	$DBH->do($struct);
	if ($DBI::errstr) {
		warn "INFO ".$DBI::errstr."\n";
	}	

	# my $seq ="CREATE SEQUENCE sq_$TABLENAME 
	#			MINVALUE 1
	#			MAXVALUE 999999999
	#			START WITH 1
	#			INCREMENT BY 1;";
	#$dbh->do("$seq");

	$DBH->commit();	# n�cessaire si AutoCommit  vaut 0
	$DBH->disconnect();
1;
}


sub drop_Track_Table(){
	&prepare_Tracking_Env();
	&open_DBI();
	
	print "=> Drop table $ENV{EDTK_DBI_TABLENAME}, if exist\n\n";
	$DBH->do("DROP TABLE $ENV{EDTK_DBI_TABLENAME}");
	$DBH->disconnect;

1;
}


sub fetchall_DBI(;$) {
	# Connexion � une table DBI pour select vers une r�f�rence de tableau
	# s�lection de toutes les donn�es correspondant � un crit�re
	# option : requete � passer, exemple "SELECT * FROM TRACKING_OEDTK WHERE ED_MOD_ED = 'T'"
	#		par defaut vaut 'SELECT * from $ENV{EDTK_DBI_TABLENAME}' 
	my $request =shift;
	$request ||="SELECT * from $ENV{EDTK_DBI_TABLENAME}";
	
	my $sql = qq($request); 
	my $sth = $DBH->prepare( $sql );
	$sth->execute () 
			|| warn "ERR. DBI exec " . $DBH->errstr ; 
	
	my $rTab = $sth->fetchall_arrayref;
	
	$sth->{Active} = 1;	# resolution du bug SQLite "closing dbh with active statement" http://rt.cpan.org/Public/Bug/Display.html?id=9643
	$sth->finish();
	#$DBH->commit();	# n�cessaire si AutoCommit  vaut 0 ???
	if ($DBI::errstr) {
		warn $DBI::errstr."\n";
	}	

return $rTab;
}


sub edit_All_rTab($){
	# Edition de l'ensemble des donn�es d'un tableau pass� en ref�rence
	#  affichage du tableau en colonnes 
	my $rTab=shift;

	for (my $i=0 ; $i<=$#{$rTab} ; $i++) {
		my $cols = $#{$$rTab[$i]};
		print "\n$i:\t";
			
		for (my $j=0 ;$j<=$cols ; $j++){
			print "$$rTab[$i][$j]\t";
		}
	}
	print "\n";

1;
}


sub subClose_DB(){
	$DBH->commit() if ($ENV{EDTK_DBI_AutoCommit} eq 0 );	# n�cessaire si AutoCommit  vaut 0
#	$DBH->disconnect();
1;
}

END {
	if (exists $h_subClose{EDTK_TRACK_MODE}) {
		&{$h_subClose{$ENV{EDTK_TRACK_MODE}}} ;
	}
}
1;




# NOTES 
#
# LISTE DES TABLES
# select table_name from tabs;
#
# Lister les tables du sch�ma de l'utilisateur courant :
# SELECT table_name FROM user_tables;
#
# Lister les tables accessibles par l'utilisateur :
# SELECT table_name FROM all_tables;
#
# Lister toutes les tables (il faut �tre ADMIN) :
# SELECT table_name FROM dba_tables; 
#
# DESCRIPTION DE LA TABLE :
# desc matable; 	# retourne les champs et leurs types 



# EXEMPLES REQUETES - http://fadace.developpez.com/sgbdcmp/fonctions/
#
# SELECT * FROM TRACKING_OEDTK WHERE ED_JOB_EVT='S';
# SELECT * FROM TRACKING_OEDTK WHERE ED_MOD_ED='T';
# SELECT SUM(ED_OBJ_COUNT) AS "OBJETS" FROM TRACKING_OEDTK WHERE ED_JOB_EVT='D';
# SELECT COUNT(ED_OBJ_COUNT) AS "OBJETS" FROM TRACKING_OEDTK WHERE ED_JOB_EVT='D';
# SELECT DISTINCT ED_SNGL_ID FROM TRACKING_OEDTK;
# SELECT COUNT (DISTINCT ED_SNGL_ID) FROM TRACKING_OEDTK ;
# SELECT COUNT (DISTINCT ED_SNGL_ID) FROM TRACKING_OEDTK WHERE ED_JOB_EVT='D';
# SELECT COUNT (DISTINCT ED_SNGL_ID) AS "TOTAL" FROM TRACKING_OEDTK  WHERE ED_JOB_EVT='D' AND ED_MOD_ED='T';
# SELECT ED_TSTAMP, ED_APP, ED_SNGL_ID FROM TRACKING_OEDTK WHERE ED_MOD_ED='T' AND ED_JOB_EVT='S';
# SELECT  to_char(ED_TSTAMP, 'DD/MM/YYYY HH24:MM:SS'), ED_APP, ED_SNGL_ID FROM TRACKING_OEDTK WHERE ED_MOD_ED='T' AND ED_JOB_EVT='S';
# SELECT  to_char(ED_TSTAMP, 'DD/MM/YYYY HH24:MM:SS') AS TIME , ED_APP, ED_SNGL_ID FROM TRACKING_OEDTK WHERE ED_MOD_ED='B' AND ED_JOB_EVT='S';


#
# END
