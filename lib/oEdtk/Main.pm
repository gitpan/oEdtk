package oEdtk::Main;

use strict;
use warnings;

use Exporter;
our $VERSION 	=0.6102;
our @ISA	=	qw(Exporter);
our @EXPORT 	= 	qw(
			c7Flux
			clean_adress_line
			date2time
			fiEdtkOpen
			fmt_address
			fmt_address_sender
			fmt_date
			fmt_monetary
			foEdtkClose
			foEdtkOpen
			get_aneto_user
			get_sycomore_user
			maj_sans_accents
			oe_maj_sans_accents
			mnt2txtUS
			mntSignX
			nowTime
			oe_cdata_table_build
			oe_compo_set_value
			oe_csv2data_handles
			oe_data_build
			oe_date_smallest
			oe_date_biggest
			oe_define_TeX_output
			oe_env_var_completion
			oe_ID_LDOC
			oe_num2txt_us
			oe_outmngr_compo_run
			oe_outmngr_full_run
			oe_outmngr_output_run
			oe_unique_data_name
			oe_corporation_file_prefixe
			oe_corporation_tag
			oe_corporation_get
			oe_corporation_set
			oe_set_sys_date
			prodEdtk_Current_Rec
			prodEdtk_Previous_Rec
			prodEdtk_rec
			prodEdtkAppUsage
			prodEdtkClose
			prodEdtkOpen
			recEdtk_erase
			recEdtk_join_tmplte
			recEdtk_motif
			recEdtk_output
			recEdtk_post_process
			recEdtk_pre_process
			recEdtk_process
			recEdtk_redefine
			toC7date
			toDate
			trimSP
			trtEdtk_Add_Value
			trtEdtkEnr
			*OUT *IN  @DATATAB $LAST_ENR
			%motifs %ouTags %evalSsTrt
			);

use POSIX			qw(mkfifo);
use List::Util 	qw(reduce);
use List::MoreUtils	qw(uniq);
use Getopt::Long;
use Date::Calc 	qw(Add_Delta_Days Delta_Days Date_to_Time Today Gmtime Week_of_Year);
use File::Basename;
use Sys::Hostname;

require oEdtk::libC7;
require oEdtk::Outmngr;
use oEdtk::Dict;
use oEdtk::Config 	qw(config_read);
use oEdtk::Run		qw(oe_status_to_msg oe_compo_run oe_after_compo oe_outmngr_output_run_tex);


#
# CODE - DOC AT THE END
#

# METHODE GENERIQUE D'EXTRACTION ET DE TRAITEMENT DES DONNEES

 our @DATATAB;			# le tableau dans lequel les enregistrements sont ventilés
 					# changer en OE_DATATAB
 our $LAST_ENR		="";	# QUID LAST_ENR ????
 our $CURRENT_REC	="";	# enrgistrement courant
 our $PREVIOUS_REC	="";	# enregistrement précédent

 our %motifs;			#rendre privée
 our %ouTags;			#rendre privée
 our %evalSsTrt;		#rendre privée

 my $_ID_LDOC		='';	# initialisation de l'identifiant unique de document (un par run)
 my $PUSH_VALUE	="";


# PLANNED : CONFIGURATION OF OUTPUT SYSTEM
# 		return "\\long\\gdef\\$name\{$value\}";
my $TAG_MODE = 'C7';
my ($TAG_OPEN, $TAG_CLOSE, $TAG_MARKER, $TAG_ASSIGN, $TAG_ASSIGN_CLOS, $TAG_COMMENT, $TAG_L_SET, $TAG_R_SET);

sub oe_define_TeX_output(){
	$TAG_MODE = 'TEX';
	# \\long\\gdef\\$name\{$value\}
	# \long\gdef\NUMCONT{000014770}
	# \long\gdef\PRENOM{MIREILLE}\long\gdef\DATE{01/08/2009}\long\gdef\NICY{10}\STARTGAR
	$TAG_OPEN	= "\\";		# une ouverture de balise (open)
	$TAG_CLOSE	= "";		# une fermeture de balise (close)
	$TAG_MARKER	= "";		# un marqueur de début de balise 
	$TAG_ASSIGN	= "long\\gdef\\\{";	# un marqueur d'attribution de valeur 
	$TAG_ASSIGN_CLOS= "\}"; 	# un marqueur fermeture d'attribution de valeur
	$TAG_COMMENT	= "%";		# un commentaire (rem)
	$TAG_L_SET	= "";		# attribution de variable : partie gauche
	$TAG_R_SET	= "";		# attribution de variable : partie droite

# \long\gdef\xProdApp\}
1;
}
oe_define_TeX_output();		# valeurs par défaut


sub oe_define_Compuset_output(){
	# <#xAppRef=PRRPC-ADCOMS>
	$TAG_MODE	= 'C7';
	$TAG_OPEN	= '<';		# une ouverture de balise (open)
	$TAG_CLOSE	= '>';		# une fermeture de balise (close)
	$TAG_MARKER	= '#';		# un marqueur de début de balise 
	$TAG_ASSIGN	= '=';		# un marqueur d'attribution de valeur 
	$TAG_ASSIGN_CLOS= ''; 		# un marqueur fermeture d'attribution de valeur
	$TAG_COMMENT	= '<SK>';	# un commentaire (rem)
	$TAG_L_SET	= '<SET>';	# attribution de variable : partie gauche
	$TAG_R_SET	= '<EDIT>';	# attribution de variable : partie droite
1;
}


	sub recEdtk_erase ($){		# migrer oe_rec_erase
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

	sub recEdtk_redefine ($$){		# migrer oe_rec_redefine
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


	sub recEdtk_motif ($$){		# migrer oe_rec_motif
		# FONCTION POUR DÉCRIRE LE MOTIF UNPACK DE L'ENREGISTREMENT
		#
		#  appel :
		# 	recEdtk_motif ($keyRec, "A2 A10 A15 A10 A15 A*");
		my $keyRec=shift;
		my $motif =shift;
		$motifs{$keyRec}=$motif;	
	1;
	}

	sub recEdtk_join_tmplte ($$$){		# migrer oe_rec_joined_descriptors
		# FONCTION POUR COMPLÉTER LES DESCRIPTIF DU MOTIF UNPACK DE L'ENREGISTREMENT
		# ET DU FORMAT DE SORTIE EN PARALLÈLE
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
		$ouTags{$keyRec}=~s/^\-1//; # lorsque recEdtk_join_tmplte est utilisé pour définir ouTags dynamiquement en cours de trtEdtkEnr, la valeur par défaut de ouTags = '-1' (pas de traitement) => on le retire pour ne pas polluer la sortie
	1;
	}


	sub recEdtk_output ($$){		# migrer oe_rec_output
		# FONCTION POUR DÉCRIRE LE FORMAT DE SORTIE DE L'ENREGISTREMENT POUR SPRINTF
		#
		#  appel :
		# 	recEdtk_output ($keyRec, "<#GESTION=%s><#PENOCOD=%s><#LICCODC=%s><SK>%s");
		my $keyRec=shift;
		my $format=shift;
		$ouTags{$keyRec}=$format;	
	1;
	}

	sub recEdtk_pre_process ($$){		# migrer oe_rec_pre_process
		# FONCTION POUR ASSOCIER UN PRÉ TRAITEMENT À UN ENREGISTREMENT
		#  ce traitement est effectué avant le chargement de l'enregistrement dans DATATAB
		#  le contenu de l'enregistrement précédent est toujours disponible dans DATATAB
		#  le type de l'enregistrement courant est connu dans le contexte d'execution
		# 
		#  appel :
		# 	recEdtk_pre_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[0]=$refFonction;
	1;	
	}

	sub recEdtk_process ($$){		# migrer oe_rec_process
		# FONCTION POUR ASSOCIER UN TRAITEMENT À UN ENREGISTREMENT
		#  ce traitement est effectué juste après le chargement de l'enregistrement dans DATATAB
		#
		#  appel :
		# 	recEdtk_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[1]=$refFonction;	
	1;
	}

	sub recEdtk_post_process ($$){		# migrer oe_rec_post_process
		# FONCTION POUR ASSOCIER UN POST TRAITEMENT À UN ENREGISTREMENT
		#  ce traitement est effectué juste après le reformatage de l'enregistrement dans format_sortie
		#  la ligne d'enregistrement est connu dans le contexte d'exécution, dans sa forme "format_sortie"
		#
		#  appel :
		# 	recEdtk_post_process ($keyRec, \&fonction);
		my $keyRec=shift;
		my $refFonction=shift;
		$evalSsTrt{$keyRec}[2]=$refFonction;	
	1;
	}

	sub prodEdtk_rec ($$\$;$$) {		# migrer oe_process_ref_rec
		# ANALYSE ET TRAITEMENT COMBINES DES ENREGISTREMENTS
		#  il encapsule l'analyse et le traitement complet de l'enregistrement (trtEdtkEnr)
		#  il faut un appel par longueur de cle, dans l'ordre décroissant (de la cle la plus stricte à la moins contraingnante)
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
			# l'enregistrement a été identifié et traité
			# on édite l'enregistrement 
			print OUT ${$refLigne};
			return 1;
		}
	# SINON ON A PAS RECONNU L'ENREGISTREMENT, C'EST UN ECHEC
	return 0;
	}

	sub trtEdtkEnr ($\$;$$){		# migrer oe_trt_ref_rec
		# TRAITEMENT PRINCIPAL DES ENREGISTREMENTS
		# MÉTHODE GÉNÉRIQUE V0.2.1 27/04/2009 10:05:03 (le passage de référence devient implicite)
		# LA FONCTION A BESOIN DU TYPE DE L'ENREGISTEMENT ET DE LA RÉFÉRENCE À UNE LIGNE DE DONNÉES
		#  appel :
		#	trtEdtkEnr($Rec_ID, $ligne [,$offsetRec,$lenRec]);
		#  retourne : statut, $Rec_ID
		my $Rec_ID	=shift;
		my $refLigne	=shift;
		my $offsetRec	=shift;		# OFFSET OPTIONNEL DE DONNÉES À SUPPRIMER EN TÊTE DE LIGNE
		my $lenRec	=shift;		# LONGUEUR ÉVENTUELLE DE DONNÉEES À TRAITER
		# VALEURS PAR DÉFAUT
		$ouTags{$Rec_ID} 	||="-1"; 
		$motifs{$Rec_ID} 	||="";
		$offsetRec 		||=0;
		$lenRec			||="";

		# SI MOTIF D'EXTRACTION DU TYPE D'ENREGISTREMENT N'EST PAS CONNU,
		#  ET SI IL N'Y A AUCUN PRE TRAITEMENT ASSOCIÉ AU TYPE D'ENREGISTREMENT,
		#  ALORS LE TYPE D'ENREGISTREMENT N'EST PAS CONNU
		#
		# CE CONTRÔLE PERMET DE DÉFINIR DYNAMIQUEMENT UN TYPE D'ENREGISTREMENT EN FOCNTION DU CONTEXTE
		#  C'EST A DIRE QU'UN ENREGISTREMENT TYPÉ "1" POURRA AVOIR DES CARACTÉRISITQUES DIFFÉRENTES
		#  EN FONCTION DU TYPE D'ENREGISTREMENT TRAITÉ PRÉCÉDEMMENT.
		#  CES CARACTÉRISITIQUES PEUVENT ÊTRE DÉFINIES AU MOMENT DU PRÉ TRAITEMENT.
		#
		if ($motifs{$Rec_ID} eq "" && !($evalSsTrt{$Rec_ID}[0])) {
			warn "INFO : trtEdtkEnr() > LIGNE $. REC. >$Rec_ID< (offset $offsetRec) UNKNOWN\n";
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
				or die "ERROR: trtEdtkEnr() > LIGNE $. typEnr >$Rec_ID< motif >$motifs{$Rec_ID}< UNKNOWN\n";
		
		# STEP 1 : EVAL TRAITEMENT CHAMPS
		&{$evalSsTrt{$Rec_ID}[1]} if $evalSsTrt{$Rec_ID}[1];
		
		# STRUCTURATION DE L'ENREGISTREMENT POUR SORTIE
		if ($ouTags{$Rec_ID} ne "-1"){
			${$refLigne}  ="${TAG_OPEN}a${Rec_ID}${TAG_CLOSE}";
			${$refLigne} .=sprintf ($ouTags{$Rec_ID},@DATATAB) 
						or die "ERROR: trtEdtkEnr() > LIGNE $. typEnr >$Rec_ID< ouTags >$ouTags{$Rec_ID}<\n";
			${$refLigne} .="${TAG_OPEN}e${Rec_ID}${TAG_CLOSE}\n";
		} else {
			${$refLigne}="";
		}
		$LAST_ENR=$Rec_ID;
		
		# STEP 2 : EVAL POST TRAITEMENT
		&{$evalSsTrt{$Rec_ID}[2]} if $evalSsTrt{$Rec_ID}[2];
	
		# ÉVENTUELLEMENT AJOUT DE DONNÉES COMPLÉMENTAIRES 
		${$refLigne} .=$PUSH_VALUE;
		$PUSH_VALUE ="";	
		${$refLigne} =~s/\s{2,}/ /g;	#	CONCATÉNATION DES BLANCS
		#$LAST_ENR=$Rec_ID;

	return 1, $Rec_ID;
	}

	sub trtEdtk_Add_Value ($){		# migrer oe_rec_cdata_join
		$PUSH_VALUE .=shift;
	1;
	}

	sub prodEdtk_Previous_Rec () {		# migrer oe_previous_rec
		return $PREVIOUS_REC;
	}
	
	sub prodEdtk_Current_Rec () {		# migrer oe_current_rec
		return $CURRENT_REC;
	}


sub mntSignX(\$;$) {		# migrer oe_num_sign_x
	# traitement des montants signés alphanumeriques
	# recoit : une reference a une variable alphanumerique
	#          un nombre de décimal après la virgule (optionnel, 0 par défaut)

	my ($refMontant, $decimal)=@_;
	${$refMontant}	||="";
	$decimal		||=0;

	# controle de la validite de la valeur transmise
	${$refMontant}=~s/\s+//g;
	if (${$refMontant} eq "" || ${$refMontant} eq 0) {
		${$refMontant} =0;
		return 1;
	} elsif (${$refMontant}=~/\D{2,}/){
		warn "INFO : value (${$refMontant}) not numeric.\n";
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
 		# warn "INFO : MONTANT SIGNE";
  	} elsif (${$refMontant}=~/^-{1}/){
		# une valeur avec un signe negatif -123456
	}

	${$refMontant}=${$refMontant}/(10**$decimal);

return ${$refMontant};
}

sub date2time ($){		# migrer oe_date_to_time
	# FONCTION DÉPRÉCIÉE, 
	# UTILISER LA BIBLIOTHÈQUE SPÉCIALISÉE : Date::Calc
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
		# date est plus récent
		$decalage=+1;
	}

	while ($date ne $tmpDate){
		$jours++;
		# une journée comporte 86400 secondes
		($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
			gmtime($time+($decalage*$jours*86400));
		$tmpDate=sprintf ("%4.0f%02.0f%02.0f", $year+1900, $mon+1, $mday);
	}

return ($time+($decalage*$jours*86400)), ($decalage*$jours);
}

sub nowTime(){			# migrer oe_now_time
	# FONCTION DÉPRÉCIÉE, 
	# UTILISER LA BIBLIOTHÈQUE SPÉCIALISÉE : Date::Calc -> Today

	my $time =time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) =
		gmtime($time);
	$time =sprintf ("%4.0f%02.0f%02.0f%02.0f%02.0f%02.0f", $year+1900, $mon+1, $mday, $hour, $min, $sec);

return $time;	
}

# Le dictionnaire des abbréviations.
my $_DICO_POST;

sub clean_adress_line(\$) {	# migrer oe_clean_adr_line
	# CETTE FONCTION PERMET UN NETTOYAGE DES LIGNES D'ADRESSE POUR CONSTRUIRE LES BLOCS D'ADRESSE DESTINTATIRE
	# elle travaille sur la référence de la variable directement mais retourne aussi la chaine resultante
	my $rLine = shift;

	# valeur par défaut dans le cas où le champs serait undef
	if (!defined($rLine) || length($$rLine) == 0) {
		$$rLine = '';
		return $$rLine;
	}

	chomp($$rLine);	# pour être sûr de ne pas avoir de retour à la ligne en fin de champ
	trimSP($rLine);
	
	# faire une expression régulière qui traite tout ce qui n'est pas 0-9\-\°\w par des blancs
	$$rLine =~ s/\./ /g;	# on remplace les points
	$$rLine =~ s/\,/ /g;	# on remplace les virgules
	$$rLine =~ s/\:/ /g;	# on remplace les points virgules
	$$rLine =~ s/\;/ /g;	# on remplace les points virgules
	$$rLine =~ s/\// \/ /g;	# on ajoute des espaces autour de '/' dans les adresses
	$$rLine =~ s/\(/ /g;	# on remplace les parenthèses ouvrantes
	$$rLine =~ s/\)/ /g;	# on remplace les parenthèses fermantes
	$$rLine =~ s/\²/ /g;	# on remplace les '²' (touche au-dessus de TAB)
	$$rLine =~ s/\~/ /g;	# on remplace les '~' (touche alpha num 2)
	$$rLine =~ s/\]/ /g;	# on remplace les ']' (touche alpha num °)
	$$rLine =~ s/\[/ /g;	# on remplace les ']' (pas d'explication...)
	
	$$rLine =~ s/^\s+//;	# on supprime les blancs consécutifs en début de chaîne (on a fait un trimSP en premier...)
	$$rLine =~ s/\s+$//;	# on supprime les blancs consécutifs en fin de chaîne (...)
	$$rLine =~ s/^0\s+//;	# on supprime les zéros tout seul en début de chaine (on le passe en dernier, après les trim)

	# Use the given dictionary to translate words.
	if (length($$rLine) > 38) {
		if (!defined($_DICO_POST))  {
			my $cfg = config_read();
			$_DICO_POST = oEdtk::Dict->new($cfg->{'EDTK_DICO_POST'});
		}
		my @words = split(/ /, $$rLine);
		$$rLine = join(' ', map { $_DICO_POST->translate($_) } @words);
	}
	$$rLine = sprintf("%.38s", $$rLine); # on s'assure de ne pas dépasser 38 caractères par lignes

	# POUR ÉVITER L'UTILISATION DES BLANCS FORCÉS ENTRE DES CHAMPS D'ADRESSE (EX : <PEADNUM>`<PEADBTQ>`<PEVONAT>`<LIBVOIX><NLIF>)
	# on rajoute un blanc en fin de champ s'il contient au moins un caractère
	if ($TAG_MODE eq "C7" && $$rLine =~ /\w+$/) {
		$$rLine .= " ";
	}
	return $$rLine;
}

sub oe_maj_sans_accents (\$) {	
	# CETTE FONCTION CONVERTIT LES CARACTÈRES ACCENTUÉS MAJUSCULES EN CARACTÈRES NON ACCENTUÉS MAJ
	# l'utilisation de la localisation provoque un bug dans la commande "sort".
	# On ne s'appuie pas sur la possibilité de rétablir le comportement par défaut par échappement
	# (la directive no locale ou lorsqu'on sort du bloc englobant la directive use locale)
	# de façon à adopter un mode de fonctionnement standard et simplifié.
	# NB : la localisation ralentit considérablement les tris.
	# (cf. doc Perl concernant la localisation : perllocale)
	#
	# l'appel de la fonction se fait par passage de référence implicite
	#	oe_char_no_accents($chaine);
	
	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/[ÀÂÄ]/A/g;
	${$refChaine}=~s/[ÉÈÊË]/E/g;
	${$refChaine}=~s/[ÌÎÏ]/I/g;
	${$refChaine}=~s/[ÒÔÖÕ]/O/g;
	${$refChaine}=~s/[ÚÙÛÜ]/U/g;
	${$refChaine}=~s/Ç/C/g;
	# on ne reprend pas la commande uc qui peut être faite avant appel à oe_maj_sans_accents
	# - soit on veut garder les minuscules accentuées, soit on veut tout capitaliser
	## ${$refChaine}= uc ${$refChaine};
	
return ${$refChaine};
}

sub maj_sans_accents (\$) {	# migrer oe_maj_sans_accents
	# CETTE FONCTION CONVERTIT LES CARACTÈRES ACCENTUÉS EN CARACTÈRES MAJUSCULES NON ACCENTUÉS
	# l'utilisation de la localisation provoque un bug dans la commande "sort".
	# On ne s'appuie pas sur la possibilité de rétablir le comportement par défaut par échappement
	# (la directive no locale ou lorsqu'on sort du bloc englobant la directive use locale)
	# de façon à adopter un mode de fonctionnement standard et simplifié.
	# NB : la localisation ralentit considérablement les tris.
	# (cf. doc Perl concernant la localisation : perllocale)
	#
	# l'appel de la fonction se fait par passage de référence implicite
	#	maj_sans_accents($chaine);
	
	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/[àâä]/a/g;
	${$refChaine}=~s/[éèêë]/e/g;
	${$refChaine}=~s/[ìîï]/i/g;
	${$refChaine}=~s/[òôöõ]/o/g;
	${$refChaine}=~s/[úùûü]/u/g;
	${$refChaine}=~s/ç/c/g;
	${$refChaine}= uc ${$refChaine};
	
return ${$refChaine};
}


sub trimSP(\$) {		# migrer oe_trimp_space
	# SUPPRESSION DES ESPACES CONSECUTIFS (TRAILING BLANK) PAR GROUPAGE
	# le parametre doit etre une reference, exemple : trimSP($chaine)
	# retourne le nombre de caracteres retires
	my $rChaine  =shift;
	${$rChaine}||="";
	${$rChaine} =~s/\s{2,}/ /go;
	
return ${$rChaine};
}

				# migrer oe_open_fi_IN
sub fiEdtkOpen ($;$){ 		# GESTION DE BASE INPUT FILE
	my $fi =shift;
	open (IN, "$fi")	or die "ERROR: ouverture $fi, code retour $!\n";

1;
}

				# migrer oe_open_fo_OUT
sub foEdtkOpen ($){ 		# GESTION DE BASE OUTPUT FILE
	my $fo =shift;
	open (OUT, "> $fo")	or die "ERROR: ouverture $fo - code retour $!\n";

1;
}


sub foEdtkClose ($) {	# migrer oe_close_fo
	my $f =shift;
	
	close (OUT) or die "ERROR: fermeture $f - code retour $!\n";
1;
}

sub toDate(\$) {		# migrer oe_to_date
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT JJ/MM/AAAA
	my $refVar  =shift;
	${$refVar}||="";
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/$3\/$2\/$1/o;

return ${$refVar};
}


sub fmt_date($) {		# migrer oe_fmt_date
	my $date = shift;

	die "ERROR: Unexpected date format: \"$date\"\n"
	    if $date !~ /^\s*(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})\s*$/;

	return sprintf("%02s/%02s/%s", $1, $2, $3);
}

# Convert a date in DD/MM/YYYY format to YYYYMMDD format.
sub oe_date_convert($) {	# oe_date_format
	my $date = shift;

	if ($date !~ /^\s*(\d{1,2})\/(\d{1,2})\/(\d{4})\s*$/) {
		return undef;
	}
	return sprintf("%d%02d%02d", $3, $2, $1);
}

sub oe_date_compare {
	my ($date1, $date2) = @_;

	if ($date1 eq '') {
		$date1=$date2;
	} 

	my $wdate1 = oe_date_convert($date1);
	my $wdate2 = oe_date_convert($date1);

	if (!defined($wdate1)) {
		warn "INFO : Unexpected date format: \"$date1\" should be dd/mm/yyyy. Date ignored\n";
		return 1;	
	}
	if (!defined($wdate2)) {
		warn "INFO : Unexpected date format: \"$date2\" should be dd/mm/yyyy. Date ignored\n";
		return -1;	
	}
	return $wdate1 <=> $wdate2;
}

sub oe_date_smallest($$) {
	my ($date1, $date2) = @_;

	if (oe_date_compare($date1, $date2) <= 0) {
		return $date1;
	} else {
		return $date2;
	}
}

sub oe_date_biggest($$) {
	my ($date1, $date2) = @_;

	if (oe_date_compare($date1, $date2) <= 0) {
		return $date2;
	} else {
		return $date1;
	}
}


sub get_aneto_user($) {		# migrer oe_aneto_get_user
	my $file = shift;

	open (my $fh, "<$file") or die $!;
	my $line = <$fh>;
	# FLUX  1169733711000000000001EDITBA    EDITAC014 AC014                D018     
	my($user, $type_edition, $flux) = unpack('x28 A10 A10 A10', $line);
	
	if ($user){ 	# dans les batch le user est sur la première ligne de données (FLUX)
		close($fh);
		return ($user, $type_edition, $flux) ;
	}
	
	$line = <$fh>;	# dans les TP le user est sur la seconde ligne (ENTETE) 
	close($fh);
	return unpack('x30 A8', $line); # en 28 on 'UT' pour les TP utilisateurs 
}


sub get_sycomore_user($) {	# migrer oe_sycomore_get_user
	my $file = shift;

	$file =~ s/^.*[\/\\]([^\/\\]+)$/$1/;
	$file =~ s/\.[^.]*$//;
	my @parts = split('_', $file);
	return $parts[$#parts];
}


sub mnt2txtUS (\$){		# migrer oe_num2txt_us
	# traitement des montants au format Texte
	# le séparateur de décimal "," est transformé en "." pour les commandes de chargement US / C7
	# le séparateur de millier "." ou " " est supprimé
	# recoit : une variable alphanumerique formattée pour l'affichage
	# 		mnt2txtUS($value);
	
	my $refMontant  =shift;	
	${$refMontant}||="";

	if (${$refMontant}){
		${$refMontant}=~s/\s+//g;	# suppression des blancs
		${$refMontant}=~s/\.//g;	# suppression des séparateurs de milliers
		${$refMontant}=~s/\,/\./g;	# remplacement du séparateur de décimal
		${$refMontant}=~s/(.*)(\-)$/$2$1/;# éventuellement on met le signe négatif devant
	} else {
		${$refMontant}=0;
	}			

return ${$refMontant};
}


sub oe_num2txt_us(\$) {
	# traitement des montants au format Texte
	# le séparateur de décimal "," est transformé en "." pour les commandes de chargement US / C7
	# le séparateur de millier "." ou " " est supprimé
	# recoit : une variable alphanumerique formattée pour l'affichage
	# 		$value = oe_num2txt_us($value);
	# ou par référence 
	# 		oe_num2txt_us($value);
	
	my $refValue  = shift;	
	${$refValue}||="";

	if (${$refValue}){
		${$refValue}=~s/\s+//g;		# suppression des blancs
		${$refValue}=~s/\.//g;		# suppression des séparateurs de milliers
		${$refValue}=~s/\,/\./g;	# remplacement du séparateur de décimal
		${$refValue}=~s/(.*)(\-)$/$2$1/;# éventuellement on met le signe négatif devant

	} else {
		${$refValue}=0;
	}			

return ${$refValue};
}


sub oe_compo_set_value ($;$){	# oe_cdata_set
	my ($value, $noedit) = @_;
	
	# A RETIRER : CERTAINS NUM SONT DÉJÀ US 
	# -> oe_compo_set_value($value) => oe_compo_set_value(oe_num2txt_us($value))
	my $result = $TAG_L_SET . oe_num2txt_us($value); 
	
	if (!$noedit) {
		$result .= $TAG_R_SET;
	}
	return $result;
}

sub oe_cdata_table_build($@){	# oe_xdata_table_build
	my $name = shift;
	my @DATATAB = shift;
	my $cdata="";
	for (my $i = 0; $i <= $#DATATAB; $i++) {
		my $elem = sprintf("%.6s%0.2d", $name, $i);
		$cdata .= oe_data_build($elem, $DATATAB[$i] || "");
	}
	#warn "\n";
return $cdata;
}

sub oe_data_build($;$) {	#oe_xdata_build
	my ($name, $val)= @_;

	if ($TAG_MODE eq 'TEX') {
		my $tag = oEdtk::TexTag->new($name, $val);
		return $tag->emit();
	}

	my $data	= "";
	if 	(defined $val) {
		# s'il s'agit d'une variable numérique
		if ($val =~ /^[\d\.]+$/) {
			$data = $TAG_OPEN . $TAG_MARKER . $name . $TAG_ASSIGN . $TAG_L_SET . 
				$val . $TAG_ASSIGN_CLOS . $TAG_CLOSE;		
		} else {
			$data = $TAG_OPEN . $TAG_MARKER . $name . $TAG_ASSIGN . 
				$val . $TAG_ASSIGN_CLOS . $TAG_CLOSE;
		}
	} elsif	(defined $name) {
		$data = $TAG_OPEN . $name . $TAG_CLOSE;
	}
	return $data;
}

################################################################################
## 		SPECIFIQUE COMPUSET A SORTIR A MOYEN TERME
################################################################################

# The newlines are important here, otherwise if you consume too much
# input in Compuset and don't process it right away, you'll get bogus
# errors at character count 16384.

sub fmt_monetary($) {	# cf oe_num2txt_us / oe_compo_set_value
	# NE SURTOUT PLUS UTILISER !
	my $mnt = shift;

	#$mnt = oe_num2txt_us($mnt);
	$mnt=~s/\s*//g;
	if ($mnt ne 0) {	# fmt_monetary zap les montants à zéro ce qui n'est pas une bonne solution (ex INCIMRI) => à corriger, mais attention régression possible sur états MHN
				# on utilise 'ne' car à ce niveau le montant peut être : '1 000.00' ou '-120.00' ou '63.00-'
		$mnt = oe_compo_set_value($mnt);
	} else {
		# Some lines have optional amounts and we don't want
		# to print 0,00 in that case.
		$mnt = '';
	}
	return $mnt;
}

sub fmt_address(@) {		# migrer c7_oe_fmt_adr 
	my @addr = map { clean_adress_line($_) } @_;
	return reduce { "$a<nlIF>$b" } @addr;
}

sub fmt_address_sender(@) {	# migrer c7_oe_fmt_sender_adr
	my $first = shift;
	my $addr = fmt_address(@_);
	return fmt_address($first) . "<nlIF/LT>$addr";
}


sub toC7date(\$) {		# migrer c7_oe_to_date
	# RECOIT UNE REFERENCE SUR UNE DATE AU FORMAT AAAAMMJJ
	# FORMATE AU FORMAT <C7J>JJ<C7M>MM><C7A>AAAA
	my $refVar  =shift;
	${$refVar}||="";
	${$refVar}=~s/(\d{4})(\d{2})(\d{2})(.*)/\<C7j\>$3\<C7m\>$2\<C7a\>$1/o;

return ${$refVar};
}

sub c7Flux(\$) {		# migrer c7_oe_ref_norm_flux
	# LES SIGNES "INFÉRIEUR" ET "SUPÉRIEUR" SONT DES DÉLÉMITEURS RÉSERVÉS À COMPUSET
	# LES FLUX MÉTIERS SONT TRAITÉS POUR REMPLACER CES SIGNES PAR DES ACCOLADES
	# A L'ÉDITION, COMPUSET RÉTABLI CES SIGNES POUR RETROUVER L'AFFICHAGE ATTENDUS
	#
	# DANS LA CONFIGURATION COMPUSET, LES LIGNES SUIVANTES SONT UTILISEES POUR RETABLIR LES CARACTERES ORIGINAUX :
	# LE CARACTÈRE { DANS LE FLUX DE DATA EST REMPLACÉ PAR LE SIGNE INFÉRIEUR À LA COMPOSITION
	#	<TF,{,<,>
	# LE CARACTÈRE } DANS LE FLUX DE DATA EST REMPLACÉ PAR LE SIGNE SUPÉRIEUR À LA COMPOSITION
	#	<TF,},>,>
	#
	# l'appel de la fonction se fait par passage de référence de façon implicite
	#	c7Flux($chaine);

	my $refChaine  =shift;
	${$refChaine}||="";
	${$refChaine}=~s/</{/g;
	${$refChaine}=~s/>/}/g;
1;
}


sub prodEdtkAppUsage() {		# migrer oe_app_usage
        my $app="";
        $0=~/([\w-]+[\.plmex]*$)/;
        $1 ? $app="application.pl" : $app=$1;
        print STDOUT << "EOF";

        Usage : $app <input_data_file> [job_name] [options]
			options :
					--help
					--massmail 	to confirm mass treatment
					--edms		to confirm edms treatment
					--cgi

		these values depends on ED_REFIDDOC config table (ie if treatment should be confirmed)
EOF
exit 1;
}


# XXX Global variable used to remember stuff from prodEdtkOpen() when we
# are in prodEdtkClose().  It would be *much* better to keep state in an
# object instance instead.
my $_RUN_PARAMS;

sub prodEdtkOpen(@) {	# migrer oe_open_files / oe_open
	@ARGV=(@ARGV, @_);
	my $params = {};
	# DEFAULT OPTION VALUES.
	my %defaults = (
		index => 0,
		massmail => 0,
		edms => 0,
		cgi	=> 0
	);

	#prodEdtkOpen(@ARGV, {index => 1});
	GetOptions(\%defaults, 'help', 'index', 'massmail', 'edms', 'cgi');
	if ($defaults{help} or $#ARGV ==-1) {
		&prodEdtkAppUsage();
		exit 0;
	}

	my $fi = $ARGV[0];	# TO KEEP COMPATIBILITY
	my $cfg = config_read('COMPO');
	#if (!defined($params)) {
	#	$params = {};
	#}

	if ($^O ne 'MSWin32') {
		$defaults{'fifo'} = 1;
	} else {
		$defaults{'fifo'} = 0;
	}

	while (my ($key, $val) = each(%defaults)) {
		if (!defined($params->{$key})) {
			$params->{$key} = $val;
		}
	}
	$params->{'doclib'} = _omngr_doclib();
	$params->{'idldoc'} = oe_ID_LDOC();

	# Override default setting if EDTK_COMPO_ASYNC is set in edtk.ini.
	my $async = $cfg->{'EDTK_COMPO_ASYNC'};
	if (defined($async) && $async =~ /^yes$/i) {
		$params->{'fifo'} = 1;
	}

	my $fo = $cfg->{'EDTK_PRGNAME'}.".txt";	# devrait être lié à TexMode
	$params->{'outfile'} = $fo;

	if ($params->{'fifo'} && $^O eq 'MSWin32') {
		warn "WARN : FIFO mode is not possible under Windows, ignoring.\n";
		$params->{'fifo'} = 0;
	}

	# If we are in FIFO mode and there is a left-over text file, the mkfifo()
	# call would fail.  If we are not in FIFO mode and there's a left-over FIFO,
	# we would hang indefinitely, so make sure to remove this file first.
	unlink($fo);

	# Handle options passed in the EDTK_OPTIONS environment variable.
	if (exists($ENV{'EDTK_OPTIONS'})) {
		my @opts = split(',', $ENV{'EDTK_OPTIONS'});
		foreach my $opt (@opts) {
			$params->{$opt} = 1;
		}
	}

	if ($params->{'fifo'}) {
		warn "INFO : Creating FIFO for output data file ($fo)\n";
		mkfifo($fo, 0700) or die "Could not create fifo: $!\n";
		my $pid = oe_compo_run($cfg->{'EDTK_PRGNAME'}, $params);
		$params->{'pid'} = $pid;
	}

	open(IN, '<', $fi)	or die "ERROR: Cannot open \"$fi\" for reading: $!\n";
	warn "INFO : input perl data is $fi\n";
	open(OUT, '>', $fo)	or die "ERROR: Cannot open \"$fo\" for writing: $!\n";
	warn "INFO : input compo data is $fo\n";

	# Remember for later use in prodEdtkClose() & oEdtk::Main.
	$_RUN_PARAMS = $params;

	print OUT oe_data_build(oe_corporation_tag());
	print OUT oe_data_build('xIdLdoc', $params->{'idldoc'});
	print OUT oe_data_build('xDebFlux');
	print OUT oe_data_build('xAppRef', $cfg->{'EDTK_PRGNAME'});
	print OUT oe_data_build('xDOCLIB', $params->{'doclib'});

	my $env = $cfg->{'EDTK_TYPE_ENV'};
	if ($env ne 'Production') {
		# On génère le filigrane de 'TEST EDITION'.
		print OUT oe_data_build('xWaterM', $cfg->{'EDTK_WATERMARKTEXT'}||' ');
		print OUT oe_data_build('xTstApp');
	} else {
		# Pas de filigrane.
		print OUT oe_data_build('xProdApp');
	}
	print OUT oe_data_build('xTYPPROD', substr($env, 0, 1));
	print OUT oe_data_build('xHOST',	 hostname());

	# Do we want to generate an index file?
	if ($params->{'index'}) {
		print OUT oe_data_build('xStOmgr');
		print OUT oe_data_build ('xHost', hostname());
	}
	print OUT $TAG_COMMENT;
	print OUT "\n";
}

sub oe_csv2data_handles () {
	undef @DATATAB;
	my $ligne 	= <IN>;
	chomp ($ligne);
	c7Flux($ligne);
	@DATATAB 	= split (/,/, $ligne);
	my $motif	= "";
	
	
	# TRANSFORME UN FICHIER CSV EN FICHIER DATA 
	# LA PREMIÈRE LIGNE DÉFINIT LES COLONNES ET LES NOMS DE BALISE
	# une balise d'exécution est ajoutée en fin de ligne = xFLigne
	# au final une balise de fin de flux est ajoutée = xFinFlux
	
	for (my $i=0; $i<=$#DATATAB; $i++){
		$DATATAB[$i] ="vide$i" if ($DATATAB[$i] eq '');
		$DATATAB[$i] =~s/\_//g;

		$motif .= sprintf ('%s%s%.8s%s', $TAG_OPEN, $TAG_MARKER, $DATATAB[$i], $TAG_ASSIGN );
		# my $tag_data =oe_unique_data_name(8, "$DATATAB[$i]", $i);
		# $motif .= sprintf ('%s%s%.8s%s', $TAG_OPEN, $TAG_MARKER, $tag_data, $TAG_ASSIGN);
		$motif .= "%s" . $TAG_ASSIGN_CLOS . $TAG_CLOSE;
	}
	$motif .= $TAG_OPEN . "xFLigne" . $TAG_CLOSE;
	$motif =~s/\s//g;
	# warn $motif . "\n";
	
	while ($ligne = <IN>) {
		@DATATAB = ();
		chomp ($ligne);
		c7Flux($ligne);
		@DATATAB= split (/,/, $ligne);
		for (my $i=0; $i<=$#DATATAB; $i++){
			if ($DATATAB[$i]=~/^\s*[\d\.\s]+$/){
				$DATATAB[$i] = $TAG_L_SET . $DATATAB[$i];
			}
		}
		$ligne	= sprintf($motif, @DATATAB) || '';
		print OUT $ligne . "\n"; #  if $ligne;
	}

1;
}


sub oe_outmngr_full_run($;$){
	my $input_fdatwork	= shift;
	my $output_format	= shift || "PDF";
	oe_outmngr_compo_run	($input_fdatwork, $output_format);
	oe_outmngr_output_run	();
1;
}

sub oe_outmngr_compo_run ($;$){
	my $input_fdatwork	= shift;
	my $output_format	= shift || "PDF";
	my $xTypTrt		= _app_typ_trt();

	import oEdtk::Outmngr	qw(omgr_import);
	import oEdtk::libC7 qw();
	use Fcntl		qw(:flock);
	use File::Copy;
	
	my $cfg 	=config_read('COMSET');
	my $script_compo=$cfg->{'EDTK_DIR_SCRIPT'} . "/" . $cfg->{'EDTK_PRGNAME'} . "." . $cfg->{'EDTK_EXT_COMP_OMGR'};
#	my $script_compo=$cfg->{'EDTK_DIR_SCRIPT'} . "/" . $cfg->{'EDTK_PRGNAME'} . $cfg->{'EDTK_TYP_ENVIRO'} . "." . $cfg->{'EDTK_EXT_COMP_OMGR'};
#	my $script_compo=$cfg->{'EDTK_DIR_SCRIPT'} . "/" . $cfg->{'EDTK_PRGNAME'} . "." . $cfg->{'EDTK_EXT_COMP_OMGR'};

	my $lockfile = $cfg->{'EDTK_DOCLIB_LOCK'};
	open(my $lock, '>', $lockfile) or die "ERROR: Cannot open lock file: $!\n";

	warn "INFO : lancement compo ($output_format, $script_compo, $input_fdatwork)\n";

	# When Compuset fails with a doclib opened in read-write mode, it corrupts the file,
	# so we have to protect against this...
	my $doclib = _omngr_doclib();
	my $DMG_path = $cfg->{'C7_DCLIB_RW'} . "/$doclib.dmg";

	warn "INFO : Acquiring exclusive lock on $lockfile...\n";
	flock($lock, LOCK_EX) or die "ERROR: Cannot acquire exclusive lock: $!\n";
	warn "INFO : Successfully acquired lock.\n";
	eval {
		if (-f $DMG_path) {
			copy($DMG_path, "$DMG_path.bak") or die "ERROR: Cannot backup \"$DMG_path\": $!\n";
		}
		if (defined $cfg->{'EDTK_TESTDATE'}) { oe_set_sys_date($cfg->{'EDTK_TESTDATE'}) };
		c7_compo ($output_format, $script_compo, $input_fdatwork, "OMGR", $doclib);
		c7_emit  ($output_format, $script_compo, $input_fdatwork, $cfg->{'EDTK_FDATAOUT'}, "OMGR", $doclib);
	};
	if ($@) {
		# There was an error, restore the backup doclib, and re-throw the error.
		copy("$DMG_path.bak", $DMG_path) or warn "INFO : Could not restore the doclib $DMG_path !\n";
		# die $@;
	}
	close($lock);

	my $idx1 	=$cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $cfg->{'EDTK_PRGNAME'} . ".idx1";

	#	warn 
	#	"INFO : OM EDTK_PRGNAME = "
	#	. $cfg->{'EDTK_PRGNAME'}
	#	. " EDTK_FTYP_DFLT = "
	#	. $cfg->{'EDTK_FTYP_DFLT'}
	#	. " EDTK_TYP_ENVIRO = "
	#	. $cfg->{'EDTK_TYP_ENVIRO'}
	#	."\n";



	omgr_import	($cfg->{'EDTK_PRGNAME'}, $idx1) if ($xTypTrt =~ /[MGTD]/); # xxxxxx c'est là qu'il faut le bon nom d'application

	if ($xTypTrt!~/D/) {
		unlink ($idx1);
		unlink ($input_fdatwork); 	
	}
		
	print "$cfg->{'EDTK_FDATAOUT'}.$output_format\n";
1;
}

sub oe_outmngr_output_run (;$){
	# le paramètre optionnel permet de fixer le type de traitement pour 
	# permettre à l'exploitation de lancer le output_run à intervalle régulier
	my $xTypTrt = _app_typ_trt(shift);

	if ( $xTypTrt !~/[MTD]/) {
		# oe_outmngr_output_run : on ne passe dans index_output qu'en cas de Mass, Debug ou Test de lotissement
		warn "INFO : traitement OM '$xTypTrt' -> lotissement suspendu\n";
		return 1;
	}

	import oEdtk::Outmngr	qw(omgr_export);
	import oEdtk::libC7 qw ();
	use	Archive::Zip	qw(:ERROR_CODES);
	use	Fcntl		qw(:flock);

	my $cfg 	=config_read('COMSET');

	warn "INFO : lancement \@tSsLots =omgr_export\n";
	my @lots = omgr_export();
	my (@tProcessed_Dclib);
	my $lockfile = $cfg->{'EDTK_DOCLIB_LOCK'};
	open(my $lock, '>', $lockfile) or die "ERROR: Cannot open lock file: $!\n";
	
	foreach (@lots) {
		my ($SsLot, $numpgs, @tDclib) = @$_;

		warn "INFO : Preparation job ticket $cfg->{'EDTK_DIR_OUTMNGR'} $SsLot pour compo - tDclib = @tDclib\n";
		my $SsLot_output_txt 	=$cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot . "." . $cfg->{'EDTK_EXT_WORK'};
		my $SsLot_output_opf 	=$cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot ; #. "." . $cfg->{'EDTK_EXT_PDF'};
		my $lib_filieres	=$cfg->{'C7_CHAINS_LIB'};

		foEdtkOpen ($SsLot_output_txt);
		fiEdtkOpen ($cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot . ".job");
		oe_csv2data_handles ();
		
		print OUT oe_data_build ("xIniPBAN");

		warn "INFO : Preparation de l'index $cfg->{'EDTK_DIR_OUTMNGR'} $SsLot pour compo\n";
		fiEdtkOpen ($cfg->{'EDTK_DIR_OUTMNGR'} . "/" . $SsLot . ".idx");
		oe_csv2data_handles;
		print OUT oe_data_build ("xFinFlux");
		foEdtkClose($SsLot_output_txt);

		warn "INFO : Composition $SsLot dans $cfg->{'EDTK_DIR_OUTMNGR'}\n";
		warn "INFO : Acquiring shared lock on $lockfile...\n";
		flock($lock, LOCK_SH) or die "ERROR: Cannot acquire lock: $!\n";
		warn "INFO : Successfully acquired lock.\n";
		eval {
			if (defined $cfg->{'EDTK_TESTDATE'}) { oe_set_sys_date($cfg->{'EDTK_TESTDATE'}) };
			c7_compo ("PDF", $lib_filieres, $SsLot_output_txt, "OMGR", @tDclib); 
			c7_emit  ("PDF", $lib_filieres, $SsLot_output_txt, $SsLot_output_opf, "OMGR", @tDclib);
		};
		flock($lock, LOCK_UN);
		die $@ if $@;	# Now that we unlocked, re-throw the error if any.

		close(IN);	# XXX OMG THIS IS A HACK!$#@#@
		warn "INFO : Packaging $cfg->{'EDTK_DIR_OUTMNGR'} $SsLot\n";
		my $zip = Archive::Zip->new();
		$zip->addFile("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.idx", "$SsLot.idx");
		$zip->addFile("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.pdf", "$SsLot.pdf");
		die "ERROR: Could not create zip archive\n"
		    unless $zip->writeToFileNamed("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.zip") == AZ_OK;

		if ($xTypTrt !~/D/) {
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.job");
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.idx");
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.txt");
			unlink("$cfg->{'EDTK_DIR_OUTMNGR'}/$SsLot.pdf");
		}

		@tProcessed_Dclib = uniq(@tProcessed_Dclib, @tDclib);
	}

	if ($xTypTrt !~/D/) {
		while (my $docLib = shift (@tProcessed_Dclib)){
			# warn "INFO : Suppr ".$cfg->{'EDTK_DIR_DOCLIB'}."/$docLib";
			unlink($cfg->{'EDTK_DIR_DOCLIB'}."/$docLib");
		}
	}
	close($lock);	# This releases locks.
	warn "INFO : Fin oe_outmngr_output_run\n";

	my @zips = map { $cfg->{'EDTK_DIR_OUTMNGR'}."/$$_[0].zip\n" } @lots;
	print @zips;
1;
}

sub prodEdtkClose (;@){		# migrer c7_oe_close_files
	# SI LE FLUX D'ENTREE FAIT MOINS DE 1 LIGNE (variable $.), SORTIES EN ERREUR
	# if ($. == 0) {
	#	# FLUX INVALIDE ARRET
	#	die 	"ERROR: uncomplete datastream\n $message \n\n";
	#}

	my @opt=@_;

	print OUT oe_data_build('xFinFlux');
	close(OUT) or die "ERROR: closing output $!\n";
	close(IN)  or die "ERROR: closing input $!\n";

	if ($TAG_MODE eq 'TEX') {
		my $cfg = config_read('COMPO');
		my $params = $_RUN_PARAMS;
		$params->{'corp'} = oe_corporation_set();
		if (@opt) {
			foreach (@opt){
				$_=~s/\-+//g;
				$params->{$_} = 1;
			}
		}

		if ($params->{'fifo'}) {
			# Disable signal handler.
			$SIG{'CHLD'} = 'DEFAULT';
			if (!defined($params->{'cldstatus'})) {
				# Wait for the LaTeX process to terminate.
				my $pid = $params->{'pid'};
				warn "INFO : Waiting for the LaTeX process to terminate ($pid)...\n";
				my $kid = waitpid($pid, 0);
				if ($kid <= 0) {
					die "ERROR: Could not collect child process status: $!\n";
				}
				$params->{'cldstatus'} = $?;
			}
			my $status = $params->{'cldstatus'};
			if ($status != 0) {
				my $msg = oe_status_to_msg($status);
				die "ERROR: LaTeX process failed: $msg\n";
			}
			warn "INFO : The LaTeX process terminated successfully.\n";
		} else {
			# Run the LaTeX process.
			oe_compo_run($cfg->{'EDTK_PRGNAME'}, $params);
		}
		oe_after_compo($cfg->{'EDTK_PRGNAME'}, $params);
	}
}

sub oe_env_var_completion (\$){
	# développe les chemins en remplaçant les variables d'environnement par les valeurs réelles
	# tous les niveaux d'imbrication définis dans les variables d'environnement sont développés
	# nécessite au préalable que les variables d'environnements soient définies
	my $rValue =shift;
	if ($^O eq "MSWin32"){
		# il peut y avoir des variables dans les variables d'environnement elles mêmes
		while (${$rValue}=~/\$/g) {
			${$rValue}=~s/\$(\w+)/${ENV{$1}}/g;
		}
		${$rValue}=~s/(\/)/\\/g;

	} else {
		# VERIFIER COMPATIBILITÉ SOUS *NIX
		while (${$rValue}=~/\$/g) {
			${$rValue}=~s/\$(\w+)/${ENV{$1}}/g;
		}
	}
return ${$rValue};
}


sub oe_ID_LDOC() {
	# UTILISE LA BIBLIOTHÈQUE : Date::Calc
	# ID du lot de document
	# format YWWWDHHMMSSPPPP.r (compuset se limite à 16 digits : 15 entiers, 1 decimal) 999999999999999.9

	if ($_ID_LDOC eq '') {		# on ne le génère qu'une fois par run : plusieurs appels dans la même instance retourne le même id
		my $time =time;
		my ($year,$month,$day, $hour,$min,$sec, $doy,$dow,$dst)=
			Gmtime($time);
		my ($week,) = Week_of_Year($year,$month,$day);

		my $pid = "$$";
		my $rnd = int(rand(10));
		if (length $pid > 5) {
			$pid = $pid/(10**((length $pid)-5));
		}
	
		$_ID_LDOC =sprintf ("%1d%02d%1d%02d%02d%02d%05d%1d", $year % 10, $week, $dow, $hour, $min, $sec, $pid, $rnd );

	}

return $_ID_LDOC;
}


{
 my $_app_typ_trt;	# type de traitement de lotissement, 
 			# valeur accessible uniquement par la méthode _app_typ_trt

	sub _app_typ_trt (;$){
		# désignation du type de traitement de lotissement (Output Management)
		# si la fonction est appelée avec un paramètre on l'attribue à $_app_typ_trt
		# si la fonction est appelée seule, on renvoie juste la valeur normée
		# par defaut la valeur est 'U' pour 'undef'
		# ON NE PEUT PAS CHANGER DE VALEUR EN COURS DE TRAITEMENT, SAUF pour passer en Test ou Debug
		# valeurs possibles :
		# - 'M' -> traitement de Masse avec lotissement
		# - 'G' -> traitement de reGroupement, lotissement en attente
		# - 'L' -> traitement édition Locale sans lotissement
		# - 'H' -> traitement homologation sans lotissement
		# - 'T' -> traitement test/homologation, lotissement en test possible
		# - 'D' -> mode Debug, conservation des fichiers intermédiaires
		# - 'U' -> 'undef' traitement sans lotissement

		# Gestion des types d'éxécution (Mass/Grouped/Local/Homol/Test/Debug/Undef) en 3 groupes :
		# - MTD -> font du Lotissement
		# - G	-> lotissement en attente
		# - LHU -> ne font pas de lotissement
		# - D   -> ne supprime pas les fichiers intermédiaires
		# - U   -> mode par défaut
		# - H   -> mode associé à l'extension 'Homologation' (-V2)


		# Nouvelle gestion d'exécution à partir de EDTK_TYPE_ENV :
		# EDTK_TYPE_ENV = Production	-> cleanup, si mode indexé : détermination des trt à partir de EDTK_REFIDDOC 
		# EDTK_TYPE_ENV = Integration	-> cleanup, bandeau, si mode indexé : détermination des trt à partir de EDTK_REFIDDOC
		# EDTK_TYPE_ENV = Test		-> bandeau, si mode indexé : détermination des trt à partir de EDTK_REFIDDOC
		# EDTK_TYPE_ENV = Development	-> cleanup, bandeau, traitement 'court'

		my $xTypTrt	= shift || '';
		if (defined $_app_typ_trt && $xTypTrt!~/^[TD]/i) {return $_app_typ_trt ;}
		# seules les types Test et Debug permettent de changer $_app_typ_trt s'il est déjà défini
	
		if ($xTypTrt !~ /^([MGLHTDU])/i){
			$_app_typ_trt='U';	
	
		} elsif ($xTypTrt =~ /^([MGL])/i) {
			$_app_typ_trt=$1;

		} elsif ($xTypTrt =~ /^([HTD])/i) {
			$_app_typ_trt=$1;
		}
	
	warn "INFO : type de traitement OM = $_app_typ_trt (Mass/Grouped/Local/Homol/Test/Debug/Undef)\n";
	return $_app_typ_trt;
	}
}

{
 my $_DOCLIB;		# DESIGNTAION DE LA DCLIB pour le lotissment 
 			# valeur accessible uniquement par la méthode _omngr_doclib

	sub _omngr_doclib (;$$){
		if (defined $_DOCLIB) { return $_DOCLIB ; }
	
		my $doclib	=shift;
		if (!defined $doclib){
			my $cfg = config_read('ENVDESC');
			my $ext		=shift || $cfg->{'EDTK_EXT_DEFAULT'};
			$_DOCLIB = "DCLIB_" . oe_ID_LDOC() . "." . $ext;
			#$_DOCLIB =~ s/\./_/;
		} else {
			$_DOCLIB=$doclib;
		}
	
	return $_DOCLIB;
	}
}


sub oe_corporation_file_prefixe($;$){
	my($filename, $directories, $suffix) = fileparse(shift);
	my $sep = shift || '.';
	my @prefix = split (/$sep/, $filename);
	oe_corporation_set ($prefix[0]);
	# warn "$filename \$prefix[0] $prefix[0] -> ". oe_corporation_set()."\n";
1;
}

sub oe_corporation_tag() {
	return (sprintf ("x%.7s", oe_corporation_set()) );
}


my $_xCORPOR;
my $_DICT;

sub oe_corporation_get() {
	return $_xCORPOR;
}

	sub oe_corporation_set(;$){
		# UTILISATION DICTIONNAIRE :
		#	- si paramètre connu dans le dictionnaire => valeur du dictionnaire
		#	- si paramètre inconnu dans le paramètre => valeur par défaut (edtk.ini / EDTK_CORP)
		#	- si aucun paramètre => dernière valeur connue
		my $parametre = shift;

		if (!defined($_DICT)) {
			my $cfg =config_read();
			$_xCORPOR = $cfg->{'EDTK_CORP'};	# Valeur par défaut
			$_DICT = oEdtk::Dict->new($cfg->{'EDTK_DICO'}, { invert => 1 });
		}

		my $entity;
		if (defined($parametre)) {
			$entity = $parametre;
		} else {
			$entity = $_xCORPOR;
		}

		$entity = $_DICT->translate($entity, 1);
		
		if (defined ($entity)) {
			# si la valeur a été trouvée dans le dictionnaire
			$_xCORPOR = $entity;		
		}

		# warn "\$entity $entity \$_xCORPOR $_xCORPOR\n";
		return $_xCORPOR;
	}



{			# en cours pas encore opérationnel (récup du générateur)
 my $cpt_sub_call =0; 	# variable constante propre a la fonction
 my %hListeId;

	sub oe_unique_data_name ($$;$) {
		# definition d'un identifiant unique sur n caracteres
		# les 6 premiers caracteres de la clef transmises sont extraits
		# si l'id est deja connu, on prend les 4 premiers et on ajoute un compteur sur 3 (correspond a la séquence des appels)
		# s'il est n'est toujours pas unique, on prend les 3 premiers caracteres et on complète le compteur sur 3 par un caractere
		# recoit : 	- le nombre de caractères total à retourner
		#		- un identifiant
		#		- optionnel : une reference a une valeur de compteur (3 numerique)

		my ($nb_car, $id, $cpt_value) =@_;
		if ($nb_car lt 6) { $nb_car = 6 ; }

		if ($cpt_value) {$cpt_sub_call=$cpt_value} else {$cpt_sub_call++};

		my $debut = $nb_car-2;
		my $motif ="%-" . $debut . "." . $debut . "s%0.2d"; # "%-4.4s%0.2d"
		warn "$motif / $id\n";
		$id	=sprintf ("$motif", $id);
		$id	=~s/\s/x/g;

		if (exists ($hListeId{$id})){
			$debut	= $nb_car-3;
			$motif	="%-" . $debut . "." . $debut . "s%0.3d"; # "%-3.3s%0.3d"
			$id	=sprintf ($motif ,$id, $cpt_sub_call);

			my $cpt	=97;    # pour le caractere "a"
			while (exists ($hListeId{$id})) {
				$debut	= $nb_car-4;
				$motif	="%-" . $debut . "." . $debut . "s%0.3d"; # "%-3.3s%0.3d"
				$id	=sprintf ($motif, $id, $cpt_sub_call, chr($cpt++));
				die "ERROR: impossible de creer une clef unique" if ($cpt >= 123);

				# use Log::Log4perl;
				# Log::Log4perl->init("log.conf"); => read log.conf
				# $logger = Log::Log4perl->get_logger("");
				# $logger->logdie("impossible de creer une clef unique") if ($cpt >= 123);
				# $logger->trace("...");  # Log a trace message
				# $logger->debug("...");  # Log a debug message
				# $logger->info("...");   # Log a info message
				# $logger->warn("...");   # Log a warn message	/ $logger->error_warn("..."); (comprend l'appel à warn() )
				# $logger->error("...");  # Log a error message	/ $logger->logdie ("..."); (comprend l'appel à die() )
				# $logger->fatal("...");  # Log a fatal message
			}
		}
		$hListeId{$id}=1;
	return $id;
	}
}

{
my $_backup_date ;

	sub oe_set_sys_date($) {
		my $requested_date = shift;

		my $time = time;
		my ($year,$month,$day, $hour,$min,$sec, $doy,$dow,$dst) =
			Gmtime($time);
	
		my $commande = sprintf ("date %s", $requested_date);
		warn "INFO : $commande\n";
				
		eval {
			system($commande);
		};

		if ($?){
			warn "ERROR: echec commande $commande\n";
			return -1;
		}
		
		if (!defined $_backup_date) {
			$_backup_date = sprintf ("%02s-%02s-%02s", $day, $month, $year);
		}
	return $_backup_date;
	}
	
	sub _restore_sys_date {
		oe_set_sys_date($_backup_date) if (defined $_backup_date);
	1;
	}
}


END {
	_restore_sys_date;
}
1;
