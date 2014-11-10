package oEdtk::prodEdtk;
use strict;

BEGIN{
		use Exporter ();
		use vars 	qw($VERSION @ISA @EXPORT); # @EXPORT_OK %EXPORT_TAGS);
		$VERSION 	=0.422;
		@ISA 	= qw(Exporter);
		@EXPORT 	= qw(
					prodEdtk_Current_Rec
					prodEdtk_Previous_Rec
					prodEdtk_rec		trtEdtkEnr
					prodEdtkOpen		prodEdtkClose
					fiEdtkOpen		foEdtkOpen
					foEdtkClose		prodEdtkAppUsage

					parse_data_spool
					set_C7_number		emit_C7		emit_C7_number

					maj_sans_accents	mntSignX		mnt2txtUS
					date2time			nowTime		toDate
					toC7date			c7Flux		trimSP
					clean_adress_line

					recEdtk_erase		recEdtk_redefine
					recEdtk_motif		recEdtk_output
					recEdtk_pre_process recEdtk_join_tmplte
					recEdtk_process
					recEdtk_post_process
					trtEdtk_Add_Value

					env_System_Completion
					*OUT *IN  @DATATAB $LAST_ENR
					%motifs %ouTags %evalSsTrt
					);
	}

#
# CODE - DOC AT THE END
#

# METHODE GENERIQUE D'EXTRACTION ET DE TRAITEMENT DES DONNEES

 our @DATATAB;			# le tableau dans lequel les enregistrements sont ventil�s
 					# changer en OEDTK_DATATAB
 our $LAST_ENR		="";	# QUID LAST_ENR ????
 our $CURRENT_REC	=""; # enrgistrement courant
 our $PREVIOUS_REC	=""; # enregistrement pr�c�dent

 our %motifs;		#rendre priv�e
 our %ouTags;		#rendre priv�e
 our %evalSsTrt;	#rendre priv�e

 my $TestAppMarkUp	="";
 my $pushValue		="";

 # PLANNED : CONFIGURATION OF OUTPUT SYSTEM
# my $PROD_EXT="-V1";
 my $C7r	="<SK>";	# un commentaire compuset (rem)
 my $C7o	="<";	# une ouverture de balise compuset (open)
 my $C7c	=">";	# une fermeture de balise compuset (close)


	sub recEdtk_erase ($){
		# FONCTION POUR SUPPRIMER LE TRAITEMENT D'UN ENREGISTREMENT
		#
		#  appel :
		# 	recEdtk_erase ($keyRec);
		my $keyRec=shift;
		$evalSsTrt{$keyRec}[0]="";
		$evalSsTrt{$keyRec}[1]="";	
		$evalSsTrt{$keyRec}[2]="";	
		$motifs{$keyRec}="";
		$ouTags{$keyRec}="-1";
	1;
	}

	sub recEdtk_redefine ($$){
		# FONCTION POUR REDEFINIR LE TRAITEMENT D'UN ENREGISTREMENT
		#
		#  appel :
		# 	recEdtk_redefine ($keyRec, "A2 A10 A15 A10 A15 A*");
		my $keyRec=shift;
		my $motif =shift;
		recEdtk_erase($keyRec);
		recEdtk_motif($keyRec, $motif);
	1;
	}


	sub recEdtk_motif ($$){
		# FONCTION POUR D�CRIRE LE MOTIF UNPACK DE L'ENREGISTREMENT
		#
		#  appel :
		# 	recEdtk_motif ($keyRec, "A2 A10 A15 A10 A15 A*");
		my $keyRec=shift;
		my $motif =shift;
		$motifs{$keyRec}=$motif;	
	1;
	}

	sub recEdtk_join_tmplte ($$$){
		# FONCTION POUR COMPL�TER LES DESCRIPTIF DU MOTIF UNPACK DE L'ENREGISTREMENT
		# ET DU FORMAT DE SORTIE EN PARALL�LE
		#
		#  appel :
		# 	recEdtk_join_tmplte ("abc", 'A2', '<#tag=%s>');
		# 	recEdtk_join_tmplte ($keyRec, $motif, $output);

		my $keyRec=shift;
		my $motif	=shift;
		$motif	||="A*";
		my $output=shift;
		$output	||="%s";
		$motifs{$keyRec}.=$motif;	
		$ouTags{$keyRec}.=$output;
		$ouTags{$keyRec}=~s/^\-1//; # lorsque recEdtk_join_tmplte est utilis� pour d�finir ouTags dynamiquement en cours de trtEdtkEnr, la valeur par d�faut de ouTags = '-1' (pas de traitement) => on le retire pour ne pas polluer la sortie
	1;
	}


	sub recEdtk_output ($$){
		# FONCTION POUR D�CRIRE LE FORMAT DE SORTIE DE L'ENREGISTREMENT POUR SPRINTF
		#
		#  appel :
		# 	recEdtk_output ($keyRec, "<#GESTION=%s><#PENOCOD=%s><#LICCODC=%s><SK>%s");
		my $keyRec=shift;
		my $format=shift;
		$ouTags{$keyRec}=$format;	
	1;
	}

	sub recEdtk_pre_process ($$){
		# FONCTION POUR ASSOCIER UN PR� TRAITEMENT � UN ENREGISTREMENT
		#  ce traitement est effectu� avant le chargement de l'enregistrement dans DATATAB
		#  le contenu de l'enregistrement pr�c�dent est toujours disponible dans DATATAB
		#  le type de l'enregistrement courant est connu dans le contexte d'execution
		# 
		#  appel :
		# 	recEdtk_pre_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[0]=$refFonction;
	1;	
	}

	sub recEdtk_process ($$){
		# FONCTION POUR ASSOCIER UN TRAITEMENT � UN ENREGISTREMENT
		#  ce traitement est effectu� juste apr�s le chargement de l'enregistrement dans DATATAB
		#
		#  appel :
		# 	recEdtk_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[1]=$refFonction;	
	1;
	}

	sub recEdtk_post_process ($$){
		# FONCTION POUR ASSOCIER UN POST TRAITEMENT � UN ENREGISTREMENT
		#  ce traitement est effectu� juste apr�s le reformatage de l'enregistrement dans format_sortie
		#  la ligne d'enregistrement est connu dans le contexte d'ex�cution, dans sa forme "format_sortie"
		#
		#  appel :
		# 	recEdtk_post_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[2]=$refFonction;	
	1;
	}

	sub prodEdtk_rec ($$\$;$$) {
		# ANALYSE ET TRAITEMENT COMBINES DES ENREGISTREMENTS
		#  il encapsule l'analyse et le traitement complet de l'enregistrement (trtEdtkEnr)
		#  il faut un appel par longueur de cle, dans l'ordre d�croissant (de la cle la plus stricte � la moins contraingnante)
		#  APPEL :
		#	prodEdtk_rec ($offsetKey, $lenKey, $ligne [,$offsetRec, $lenRec]);
		#  RETOURNE : statut
		#
		#	exemple 			if 		(prodEdtk_rec (0, 3, $ligne)){
		#					} elsif 	(prodEdtk_rec (0, 2, $ligne)){
		#						etc.
		my $offsetKey	=shift;
		my $lenKey	=shift;
		my $refLigne	=shift;
		my $offsetRec	=shift;	# optionnel
		$offsetRec	||=0;
		my $lenRec	=shift;	# optionnel
		$lenRec		||="";

		if (${$refLigne}=~m/^.{$offsetKey}(\w{$lenKey})/s && trtEdtkEnr($1,$refLigne,$offsetRec,$lenRec)){
			# l'enregistrement a �t� identifi� et trait�
			# on �dite l'enregistrement 
			print OUT ${$refLigne};
			return 1;
		}
	# SINON ON A PAS RECONNU L'ENREGISTREMENT, C'EST UN ECHEC
	return 0;
	}

	sub trtEdtkEnr ($\$;$$){
		# TRAITEMENT PRINCIPAL DES ENREGISTREMENTS
		# M�THODE G�N�RIQUE V0.2.1 27/04/2009 10:05:03 (le passage de r�f�rence devient implicite)
		# LA FONCTION A BESOIN DU TYPE DE L'ENREGISTEMENT ET DE LA R�F�RENCE � UNE LIGNE DE DONN�ES
		#  appel :
		#	trtEdtkEnr($Rec_ID, $ligne [,$offsetRec,$lenRec]);
		#  retourne : statut, $Rec_ID
		my $Rec_ID	=shift;
		my $refLigne	=shift;
		my $offsetRec	=shift;		# OFFSET OPTIONNEL DE DONN�ES � SUPPRIMER EN T�TE DE LIGNE
		my $lenRec	=shift;		# LONGUEUR �VENTUELLE DE DONN�EES � TRAITER
		# VALEURS PAR D�FAUT
		$ouTags{$Rec_ID} 	||="-1"; 
		$motifs{$Rec_ID} 	||="";
		$offsetRec 		||=0;
		$lenRec			||="";

		# SI MOTIF D'EXTRACTION DU TYPE D'ENREGISTREMENT N'EST PAS CONNU,
		#  ET SI IL N'Y A AUCUN PRE TRAITEMENT ASSOCI� AU TYPE D'ENREGISTREMENT,
		#  ALORS LE TYPE D'ENREGISTREMENT N'EST PAS CONNU
		#
		# CE CONTR�LE PERMET DE D�FINIR DYNAMIQUEMENT UN TYPE D'ENREGISTREMENT EN FOCNTION DU CONTEXTE
		#  C'EST A DIRE QU'UN ENREGISTREMENT TYP� "1" POURRA AVOIR DES CARACT�RISITQUES DIFF�RENTES
		#  EN FONCTION DU TYPE D'ENREGISTREMENT TRAIT� PR�C�DEMMENT.
		#  CES CARACT�RISITIQUES PEUVENT �TRE D�FINIES AU MOMENT DU PR� TRAITEMENT.
		#
		if ($motifs{$Rec_ID} eq "" && !($evalSsTrt{$Rec_ID}[0])) {
			warn "INFO trtEdtkEnr() > LIGNE $. REC. >$Rec_ID< (offset $offsetRec) UNKNOWN\n";
			return 0;
		}

		$PREVIOUS_REC	=$CURRENT_REC;
		$CURRENT_REC	=$Rec_ID;
	
		# STEP 0 : EVAL PRE TRAITEMENT de $refLigne
		&{$evalSsTrt{$Rec_ID}[0]}($refLigne) if $evalSsTrt{$Rec_ID}[0];
		
		# ON S'ASSURE DE BIEN VIDER LE TABLEAU DE LECTURE DE L'ENREGISTREMENT PRECEDENT
		undef @DATATAB;

		# EVENTUELLEMENT SUPPRESSION DES DONNEES NON UTILES (OFFSET ET HORS DATA UTILES (lenData))
		${$refLigne}=~s/^.{$offsetRec}(.{1,$lenRec}).*/$1/ if ($offsetRec > 0);
		
		# ECLATEMENT DE L'ENREGISTREMENT EN CHAMPS
		@DATATAB =unpack ($motifs{$Rec_ID},${$refLigne}) 
				or die "ERROR trtEdtkEnr() > LIGNE $. typEnr >$Rec_ID< motif >$motifs{$Rec_ID}< UNKNOWN\nDIE";
		
		# STEP 1 : EVAL TRAITEMENT CHAMPS
		&{$evalSsTrt{$Rec_ID}[1]} if $evalSsTrt{$Rec_ID}[1];
		
		# STRUCTURATION DE L'ENREGISTREMENT POUR SORTIE
		if ($ouTags{$Rec_ID} ne "-1"){
			${$refLigne}  ="${C7o}a${Rec_ID}${C7c}";
			${$refLigne} .=sprintf ($ouTags{$Rec_ID},@DATATAB) 
						or die "ERROR trtEdtkEnr() > LIGNE $. typEnr >$Rec_ID< ouTags >$ouTags{$Rec_ID}<\nDIE";
			${$refLigne} .="${C7o}e${Rec_ID}${C7c}\n";
		} else {
			${$refLigne}="";
		}
		$LAST_ENR=$Rec_ID;
		
		# STEP 2 : EVAL POST TRAITEMENT
		&{$evalSsTrt{$Rec_ID}[2]} if $evalSsTrt{$Rec_ID}[2];
	
		# �VENTUELLEMENT AJOUT DE DONN�ES COMPL�MENTAIRES 
		${$refLigne} .=$pushValue;
		$pushValue ="";	
		${$refLigne} =~s/\s{2,}/ /g;	#	CONCAT�NATION DES BLANCS
		#$LAST_ENR=$Rec_ID;

	return 1, $Rec_ID;
	}

	sub trtEdtk_Add_Value ($){
		$pushValue .=shift;
	1;
	}

	sub prodEdtk_Previous_Rec () {
		return $PREVIOUS_REC;
	}
	
	sub prodEdtk_Current_Rec () {
		return $CURRENT_REC;
	}


sub parse_data_spool(&) {
	# traitement de spool ligne � ligne
	# re�oit en param�tre la r�f�rence � la fonction d'analyse des lignes de donn�es
	# cette fonction doit accepter les param�tres suivants :
	#  sub process($$$$\%) {
	# 	my ($resource, $jump, $dataline, $numln, $state) = @_;

	#  sub process(\$) {
	# 	my ($resource, $jump, $ref_line, $numln, $state) = @_;

	
	my ($processfn) = @_;
	# Read the input file line by line.
	my $inres;
	my $numln;
	my %state = ();
	while (<IN>) {
		chomp;
		if (length $_ == 0) {
			warn "INFO : line $. is empty\n";
			next;
		}

		# Get the first 4 characters.
		die "ERROR : unexpected line format : \"$_\" at line $.\n"
		    unless $_ =~ /^(.{4})(.*)$/;
		my ($header, $data) = ($1, $2);

		if ($header =~ /^(\d{3}) $/) { # Cas num�ro 1.
			$inres = $1;
			# Reset state for this resource.
			$numln = 1;
			%state = ();
			$processfn->($inres, undef, $data, 1, \%state);
		} elsif ($header =~ /^   (\d)$/) { # Cas num�ro 2.
			my $jump = $1;
			if (!defined $inres) {
				die "ERROR : got seal while not in a resource at line $.\n";
			}
			$processfn->($inres, $jump, $data, ++$numln, \%state);
		} else {
			die "ERROR : unexpected line header: \"$header\" at line $.\n";
		}
	}
}



sub mnt2txtUS (\$){
	# traitement des montants au format Texte
	# le s�parateur de d�cimal "," est transform� en "." pour les commandes de chargement US / C7
	# le s�parateur de millier "." ou " " est supprim�
	# recoit : une variable alphanumerique formatt�e pour l'affichage
	# 		mnt2txtUS($value);
	
	my $refMontant  =shift;	
	${$refMontant}||="";

	if (${$refMontant}){
		${$refMontant}=~s/\s+//g;	# suppression des blancs
		${$refMontant}=~s/\.//g;		# suppression des s�parateurs de milliers
		${$refMontant}=~s/\,/\./g;	# remplacement du s�parateur de d�cimal
	} else {
		${$refMontant}=0;
	}			
1;
}

sub mntSignX(\$;$) {
	# traitement des montants sign�s alphanumeriques
	# recoit : une reference a une variable alphanumerique
	#          un nombre de d�cimal apr�s la virgule (optionnel, 0 par d�faut)

	my ($refMontant, $decimal)=@_;
	${$refMontant}	||="";
	$decimal		||=0;

	# controle de la validite de la valeur transmise
	${$refMontant}=~s/\s+//g;
	if (${$refMontant} eq "" || ${$refMontant} eq 0) {
		${$refMontant} =0;
		return 1;
	} elsif (${$refMontant}=~/\D{2,}/){
		warn "INFO value (${$refMontant}) not numeric.\n";
		return -1;
	}

	my %hXVal;
	$hXVal{'p'}=0;
	$hXVal{'q'}=1;
	$hXVal{'r'}=2;
	$hXVal{'s'}=3;
	$hXVal{'t'}=4;
	$hXVal{'u'}=5;
	$hXVal{'v'}=6;
	$hXVal{'w'}=7;
	$hXVal{'x'}=8;
	$hXVal{'y'}=9;

	if ( ${$refMontant}=~s/(\D{1})$/$hXVal{$1}/ ) {
		# une valeur avec signe negatif alphanumerique 213y => -2139
		${$refMontant}=(${$refMontant}*(-1));
  	} elsif (${$refMontant}=~/^-{1}/){
		# une valeur avec un signe negatif -123456
	}

	${$refMontant}=${$refMontant}/(10**$decimal);

1;
}

sub date2time ($){
	my $date=shift; # une date au format AAAAMMJJ
	my $tmpDate="AAAAMMJJ";
	my $decalage=0;
	my $jours=-1;
	my $time=time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
		gmtime($time);
	my $nowDate=sprintf ("%4.0f%02.0f%02.0f", $year+1900, $mon+1, $mday);

	if ($nowDate > $date){
		# date est plus ancien
		$decalage=-1;
	}elsif ($nowDate < $date){
		# date est plus r�cent
		$decalage=+1;
	}

	while ($date ne $tmpDate){
		$jours++;
		# une journ�e comporte 86400 secondes
		($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
			gmtime($time+($decalage*$jours*86400));
		$tmpDate=sprintf ("%4.0f%02.0f%02.0f", $year+1900, $mon+1, $mday);
	}
return ($time+($decalage*$jours*86400)), ($decalage*$jours);
}

sub nowTime(){
	my $time =time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
		gmtime($time);
	$time =sprintf ("%4.0f%02.0f%02.0f%02.0f%02.0f%02.0f", $year+1900, $mon+1, $mday, $hour, $min, $sec);
	return $time;	
}

sub toDate(\$) {
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT JJ/MM/AAAA
	my $refVar  =shift;
	${$refVar}||="";
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/$3\/$2\/$1/o;
1;
}


# The newlines are important here, otherwise if you consume too much
# input in Compuset and don't process it right away, you'll get bogus
# errors at character count 16384.
sub emit_C7($;$) {
	my ($name, $val) = @_;
	if (defined $val) {
		print OUT "<#$name=$val>\n";
	} else {
		print OUT "<$name>\n";
	}
1;
}

sub emit_C7_number($$) {
	my ($name, $mnt) = @_;
	emit_C7($name, set_C7_number($mnt));
}


sub set_C7_number($) {
	my $mnt = shift;
	$mnt =~ s/\s+//;
	mnt2txtUS($mnt);
	if ($mnt != 0) {
		$mnt = "<SET>$mnt<EDIT>";
	} else {
		# Some lines have optional amounts and we don't want
		# to print 0,00 in that case.
		$mnt = '';
	}
	return $mnt;
}

sub toC7date(\$) {
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT <C7J>JJ<C7M>MM><C7A>AAAA
	my $refVar  =shift;
	${$refVar}||="";
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/\<C7j\>$3\<C7m\>$2\<C7a\>$1/o;
1;
}

sub c7Flux(\$) {
	# LES SIGNES "INF�RIEUR" ET "SUP�RIEUR" SONT DES D�L�MITEURS R�SERV�S � COMPUSET
	# LES FLUX M�TIERS SONT TRAIT�S POUR REMPLACER CES SIGNES PAR DES ACCOLADES
	# A L'�DITION, COMPUSET R�TABLI CES SIGNES POUR RETROUVER L'AFFICHAGE ATTENDUS
	#
	# DANS LA CONFIGURATION COMPUSET, LES LIGNES SUIVANTES SONT UTILISEES POUR RETABLIR LES CARACTERES ORIGINAUX :
	# LE CARACT�RE { DANS LE FLUX DE DATA EST REMPLAC� PAR LE SIGNE INF�RIEUR � LA COMPOSITION
	#	<TF,{,<,>
	# LE CARACT�RE } DANS LE FLUX DE DATA EST REMPLAC� PAR LE SIGNE SUP�RIEUR � LA COMPOSITION
	#	<TF,},>,>
	#
	# l'appel de la fonction se fait par passage de r�f�rence de fa�on implicite
	#	c7Flux($chaine);

	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/</{/g;
	${$refChaine}=~s/>/}/g;
1;
}

sub clean_adress_line (\$) {
	# CETTE FONCTION PERMET UN NETTOYAGE DES LIGNES D'ADRESSE POUR CONSTRUIRE LES BLOCS D'ADRESSE DESTINTATIRE
	# elle travaille sur la r�f�rence de la variable directement mais retourne aussi la chaine resultante
	my $rLine=shift;
	${$rLine}||="";		# valeur par d�faut dans le cas o� le champs serait undef

	chomp(${$rLine});		# pour �tre s�r de ne pas avoir de retour � la ligne en fin de champ
	trimSP($rLine);
	
	${$rLine}=~s/^\s+//;	# on supprime les blancs cons�cutifs en d�but de cha�ne (on a fait un trimSP en premier...)
	${$rLine}=~s/\s+$//;	# on supprime les blancs cons�cutifs en fin de cha�ne (...)

	${$rLine}=~s/\s\,/\,/g;	# on supprime les blancs devant les virgules
	${$rLine}=~s/\,\./\,/g;	# on supprime les points derri�re les virgules (contexte adresses)
	${$rLine}=~s/^\,//;		# on supprime les virgules en d�but de cha�ne
	${$rLine}=~s/\s\./\./g;	# on supprime les espaces devant les points
	${$rLine}=~s/^\.//;		# on supprime les points en d�but de cha�ne

	# POUR �VITER L'UTILISATION DES BLANCS FORC�S ENTRE DES CHAMPS D'ADRESSE (EX : <PEADNUM>`<PEADBTQ>`<PEVONAT>`<LIBVOIX><NLIF>)
	# on rajoute un blanc en fin de champ s'il contient au moins un caract�re
	if (${$rLine} =~/\w+$/) { ${$rLine} .=" "; }

return ${$rLine};
}

sub maj_sans_accents (\$) {
	# CETTE FONCTION PERMET DE CONVERTIR LES CARACT�RES ACCENTU�S EN CARACT�RES MAJUSCULES NON ACCENTU�S
	# l'utilisation de la localisation provoque un bug dans la commande "sort".
	# On ne s'appuie pas sur la possibilit� de r�tablir le comportement par d�faut par �chappement
	# (la directive no locale ou lorsqu'on sort du bloc englobant la directive use locale)
	# de fa�on � adopter un mode de fonctionnement standard et simplifi�.
	# NB : la localisation ralentit consid�rablement les tris.
	# (cf. doc Perl concernant la localisation : perllocale)
	#
	# l'appel de la fonction se fait par passage de r�f�rence implicite
	#	maj_sans_accents($chaine);
	
	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/[���]/a/g;
	${$refChaine}=~s/[����]/e/g;
	${$refChaine}=~s/[���]/i/g;
	${$refChaine}=~s/[����]/o/g;
	${$refChaine}=~s/[����]/u/g;
	${$refChaine}= uc ${$refChaine};
	
return 1;
}

sub trimSP(\$) {
	# SUPPRESSION DES ESPACES CONSECUTIFS (TRAILING BLANK) PAR GROUPAGE
	# le parametre doit etre une reference, exemple : trimSP($chaine)
	# retourne le nombre de caracteres retires
	my $rChaine  =shift;
	${$rChaine}||="";
	return ${$rChaine} =~s/\s{2,}/ /go;
}

sub IsTestApp () {
	$TestAppMarkUp ="<editTST>";
1;
}

sub prodEdtkOpen($$;$) {
	my $fi =shift;
	my $fo =shift;
	my $single_job_id 	=shift;
	$single_job_id  	||="";
	my $appRef		=$0;
	
	open (IN,   "$fi")	or die "ERROR ouverture $fi, code retour $!\nDIE";
	open (OUT, "> $fo")	or die "ERROR ouverture $fo, code retour $!\nDIE";

	$appRef	=~/([\w-]+)\.pl$/i;
	print OUT "$TestAppMarkUp<#appRef=$1><#jobUid=$single_job_id><debFlux>";
	print OUT nowTime();
	print OUT "<SK>\n";
1;
}

sub fiEdtkOpen ($;$){ # GESTION ENTREE DANS LE CONTEXTE DE PRODUCTION EXCEL
	my $fi =shift;
	open (IN, "$fi")	or die "ERROR ouverture $fi, code retour $!\nDIE";

1;
}

sub foEdtkOpen ($){ # GESTION ENTREE DANS LE CONTEXTE DE PRODUCTION EXCEL
	my $fo =shift;
	open (OUT, "> $fo")	or die "ERROR ouverture $fo - code retour $!\nDIE";

1;
}

sub prodEdtkClose ($$){
	my ($fi,$fo)=@_;

	# SI LE FLUX D'ENTREE FAIT MOINS DE 1 LIGNE (variable $.), SORTIES EN ERREUR
	if ($. < 1) {
		print "\nANOMALIE, FLUX D'ENTREE INCOMPLET ($. lignes)\n\n";
		print  OUT  " <DEBUG>ANOMALIE DANS LE FLUX\n<QUIT,3>ANOMALIE, FLUX D'ENTREE INCOMPLET ($. lignes)";
		# FLUX INVALIDE ARRET
		die -1;
	}

	print OUT "<FinFlux>";
	print OUT nowTime();
	print OUT "<SK>\n";
	close (OUT) or die "ERROR fermeture $fo, code retour $!\nDIE";
	close (IN)  or die "ERROR fermeture $fi, code retour $!\nDIE";

1;
}

sub foEdtkClose ($) {
	my $f =shift;
	
	close (OUT) or die "ERROR fermeture $f - code retour $!\nDIE";
1;
}


sub prodEdtkAppUsage() {
        my $app="";
        $0=~/([\w-]+[\.plmex]*$)/;
        $1 ? $app="application.pl" : $app=$1;
        print STDOUT << "EOF";

        Usage : $app <fichier_entree> <fichier_sortie> [option]
EOF
exit 1;
}

END {}
1;
